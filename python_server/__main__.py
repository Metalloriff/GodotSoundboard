import asyncio
import base64
import datetime
import json
import os
import re
import subprocess
import threading
import time
import traceback
import platform
import librosa

import numpy as np
import requests
import sounddevice as sd
import soundfile as sf
import websockets
from gtts import gTTS

HOST = "127.0.0.1"
PORT = 4911
BLOCK_SIZE = 1024

CLIPPER_SAMPLE_RATE = 44100
CLIPPER_BUFFER_LENGTH = 60
CLIPPER_BLOCK_SIZE = 8192
CLIPPER_MAX_ARRAY_LENGTH = int((CLIPPER_SAMPLE_RATE / CLIPPER_BLOCK_SIZE) * CLIPPER_BUFFER_LENGTH)

paused = False
sound_file = None
seek = 0
local_volume = 0.5
remote_volume = 0.5

clipper_threads = []
clipper_devices = []
clipper_buffers = []
clipper_streams = []

def kill_existing_process():
	try:
		if platform.system() == "Linux":
			output = subprocess.check_output(f"lsof -t -i:{PORT}", shell=True)

			lines = output.decode().split("\n")
			for line in lines:
				if line and int(line) > 1:
					os.kill(line, -1)
		else:
			output = subprocess.check_output(["netstat", "-aon", "|", "findstr", f":{PORT}", "|", "findstr", "LISTENING"], shell=True)
			
			lines = output.decode().split("\n")
			for line in lines:
				if line:
					parts = line.split()
					pid = int(parts[-1])
					
					os.kill(pid, -1)
					time.sleep(1)
	except subprocess.CalledProcessError:
		pass
	return None
		
async def echo(socket):
	while True:
		try:
			message = await socket.recv()
			data = json.loads(message)
			
			asyncio.ensure_future(on_message(socket, data))
		except websockets.exceptions.ConnectionClosed:
			print("CLIENT DISCONNECTED")
			os.kill(os.getpid(), 1)

async def on_message(socket, data):
	global local_volume
	global remote_volume
	global seek
	global paused

	global clipper_threads
	global clipper_devices
	global clipper_streams
	global clipper_buffers

	try:
		print(data)
		
		if data["type"] == "RECEIVE_SETTINGS":
			local_volume = data["local_volume"]
			remote_volume = data["remote_volume"]
		if data["type"] == "PLAY_CLIP":
			if not sound_file is None: await on_message(socket, { "type": "STOP_PLAYING" })

			cable_output = await get_cable_output(socket)
			if cable_output < 0: return

			paused = False
			seek = 0

			thread = threading.Thread(target=play_sound_linux if platform.system() == "Linux" else play_sound, args=((data["fp"], cable_output, socket, asyncio.get_event_loop())))
			thread.start()

			await send_message(socket, {
				"type": "STATUS_UPDATE",
				"status": "playing",
				"fp": data["fp"]
			})
		if data["type"] == "STOP_PLAYING":
			if sound_file is None:
				await send_message({
					"type": "ERROR",
					"error": "No sounds playing currently!"
				})
				return
			
			sound_file.close()
		if data["type"] == "GEN_TTS":
			fp = "tts.mp3"

			if "export" in data:
				fp = data["export"]
			
			async def play_tts():
				if "export" in data:
					await send_message(socket, {
						"type": "MESSAGE",
						"message": f"File exported to '{fp}'!",
						"message_type": "SUCCESS"
					})
				else:
					await on_message(socket, {
						"type": "PLAY_CLIP",
						"fp": fp
					})

			if data["voice"] == "TikTok":
				response = requests.post("https://tiktok-tts.weilnet.workers.dev/api/generation", json={
					"text": data["text"],
					"voice": "en_us_001"
				})

				with open(fp, "wb") as file:
					file.write(base64.b64decode(response.json()["data"]))

				await play_tts()
				return

			google_voices = {
				"Google US": "us",
				"Google UK": "co.uk",
				"Google India": "co.in"
			}

			tts = gTTS(text=data["text"], lang="en", tld=google_voices[data["voice"]])
			tts.save(fp)

			await play_tts()
		if data["type"] == "SET_VOLUME":
			if data["device"] == "local":
				local_volume = data["volume"]
			elif data["device"] == "remote":
				remote_volume = data["volume"]
		if data["type"] == "SEEK":
			if sound_file is None: return

			seek = int(data["seek"])
			sound_file.seek(seek)
		if data["type"] == "PAUSE_PLAY":
			if sound_file is None: return

			paused = not paused

			await send_message(socket, {
				"type": "STATUS_UPDATE",
				"status": "paused" if paused else "playing"
			})
		
		if data["type"] == "CLIPPER_START":
			if len(clipper_threads) > 0:
				await send_message(socket, {
					"type": "ERROR",
					"error": "Clipper already running!"
				})
				return

			devices_query = sd.query_devices()
			for device_name in data["devices"]:
				for device in devices_query:
					if device_name.strip().lower() in device["name"].strip().lower():
						if device["hostapi"] == 0:
							clipper_devices.append({
								"index": device["index"],
								"name": device["name"]
							})
			
			if len(data["devices"]) != len(clipper_devices):
				missing_devices = []

				for device in data["devices"]:
					if device not in clipper_devices:
						missing_devices.append(device)

				await send_message(socket, {
					"type": "ERROR",
					"error": "Not all devices could be found! Missing devices: " + ", ".join(missing_devices)
				})
				return
			
			for device in clipper_devices:
				thread = threading.Thread(target=clipper_thread, args=(device["index"], socket, asyncio.get_event_loop()))
				thread.start()

				clipper_threads.append(thread)
			
			await send_message(socket, {
				"type": "CLIPPER_SET_STATUS",
				"status": "RUNNING"
			})
		if data["type"] == "CLIPPER_STOP":
			for stream in clipper_streams:
				stream.stop()
			
			clipper_devices = []
			clipper_threads = []
			clipper_streams = []
			clipper_buffers = []
		if data["type"] == "CLIPPER_EXPORT":
			if len(clipper_buffers) == 0:
				await send_message(socket, {
					"type": "ERROR",
					"error": "Clipper is not running!"
				})
				return

			now = datetime.datetime.now()
			tstr = now.strftime("%m-%d %H-%M-%S")
			files = []
			
			for i, get_buffer in enumerate(clipper_buffers):
				device_name = re.sub("\(.*?(\)|$)", "", clipper_devices[i]["name"]).strip()
				fp = os.path.join(data["directory"], f"{tstr} - {device_name}.wav")

				sf.write(fp, np.array(get_buffer(), dtype="float32").flatten(), CLIPPER_SAMPLE_RATE)
				files.append(fp)

			await send_message(socket, {
				"type": "CLIPPER_EXPORT_COMPLETE",
				"exported_clips": files
			})
	except Exception as e:
		traceback.print_exception(e)
		await send_message(socket, {
			"type": "ERROR",
			"error": str(e)
		})

def clipper_thread(device_index, socket, main_loop):
	global clipper_buffers
	global clipper_streams

	buffer = []
	clipper_buffers.append(lambda: buffer)

	def handle_block(data, bs, t, s):
		nonlocal buffer

		buffer.append(data.flatten())
		buffer = buffer[-CLIPPER_MAX_ARRAY_LENGTH:]
	
	stream = sd.InputStream(
		channels=1,
		dtype="float32",
		samplerate=CLIPPER_SAMPLE_RATE,
		device=device_index,
		blocksize=CLIPPER_BLOCK_SIZE,
		callback=handle_block
	)

	clipper_streams.append(stream)

	stream.start()

	while stream.active:
		time.sleep(1)

	asyncio.run_coroutine_threadsafe(send_message(socket, {
		"type": "CLIPPER_SET_STATUS",
		"status": "STOPPED"
	}), main_loop)

	if len(clipper_streams) > 0:
		asyncio.run_coroutine_threadsafe(on_message(socket, {
			"type": "CLIPPER_STOP"
		}), main_loop)

async def get_cable_output(socket):
	devices = sd.query_devices()
	cable_output = -1

	for device in devices:
		if device["name"].lower() == "chromium input" or ("(vb-audio virtual" in device["name"].lower() and device["hostapi"] == 0):
			cable_output = device["index"]
	
	if cable_output < 0:
		await send_message(socket, {
			"type": "ERROR",
			"error": "No VB audio cable found!"
		})
		return -1
	return cable_output

def play_sound(fp, cable_output, socket, loop):
	global seek
	global sound_file
	global paused

	sound_file = sf.SoundFile(fp)

	local_stream = sd.OutputStream(blocksize=BLOCK_SIZE, channels=sound_file.channels, samplerate=sound_file.samplerate, dtype="float32")
	remote_stream = sd.OutputStream(blocksize=BLOCK_SIZE, channels=sound_file.channels, samplerate=sound_file.samplerate, dtype="float32", device=cable_output)

	local_stream.start()
	remote_stream.start()

	seek = 0
	paused = False
	while seek + BLOCK_SIZE < len(sound_file):
		if paused: continue

		d = sound_file.read(BLOCK_SIZE, dtype="float32")

		local_stream.write(d * (local_volume * local_volume))
		remote_stream.write(d * (remote_volume * remote_volume))

		seek += BLOCK_SIZE

		asyncio.run_coroutine_threadsafe(send_message(socket, {
			"type": "SEEK",
			"seek": seek,
			"max": len(sound_file)
		}), loop)
	
	sound_file = None
	seek = 0
	paused = False

	asyncio.run_coroutine_threadsafe(send_message(socket, {
		"type": "STATUS_UPDATE",
		"status": "stopped"
	}), loop)

def play_sound_linux(fp, chromium_input, socket, loop):
	global seek
	global sound_file
	global paused

	sound_file = sf.SoundFile(fp)

	sr = 48000
	resample = sound_file.read(dtype="float32") if sound_file.samplerate == sr \
		else librosa.resample(sound_file.read(dtype="float32"), orig_sr=sound_file.samplerate, target_sr=sr)
	
	for device in sd.query_devices():
		if device["name"].lower() == "chromium input":
			chromium_input = device["index"]
	
	local_stream = sd.OutputStream(blocksize=BLOCK_SIZE, channels=sound_file.channels, samplerate=sr)
	remote_stream = sd.OutputStream(blocksize=BLOCK_SIZE, samplerate=sr, device=chromium_input)

	local_stream.start()
	remote_stream.start()

	seek = 0
	paused = False
	while seek + BLOCK_SIZE < len(resample):
		if paused: continue
		
		d = resample[seek:seek+BLOCK_SIZE]

		local_d = d * (local_volume * local_volume)
		remote_d = d * (remote_volume * remote_volume)

		if sound_file.channels == 1:
			if local_stream.channels == 2:
				local_stream.write(np.column_stack((local_d, local_d)))
			else:
				local_stream.write(local_d)
			
			if remote_stream.channels == 2:
				remote_stream.write(np.column_stack((remote_d, remote_d)))
			else:
				remote_stream.write(remote_d)
		else:
			if local_stream.channels == 2:
				local_stream.write(local_d)
			else:
				local_stream.write(np.mean(local_d, axis=0))

			if remote_stream.channels == 2:
				remote_stream.write(remote_d)
			else:
				remote_stream.write(np.mean(remote_d, axis=0))

		seek += BLOCK_SIZE

		asyncio.run_coroutine_threadsafe(send_message(socket, {
			"type": "SEEK",
			"seek": seek,
			"max": len(resample)
		}), loop)
	
	sound_file = None
	seek = 0
	paused = False

	asyncio.run_coroutine_threadsafe(send_message(socket, {
		"type": "STATUS_UPDATE",
		"status": "stopped"
	}), loop)

async def main():
	async with websockets.serve(echo, HOST, PORT):
		await asyncio.Future()

async def send_message(socket, message):
	await socket.send(json.dumps(message))

if __name__ == "__main__":
	kill_existing_process()

	asyncio.run(main())