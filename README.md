# Godot Soundboard
A simple cross-platform soundboard, TTS, and audio clipping/replay software built with Godot and Python, for Windows and Linux.

![icon](icon.svg)

# Linux notes

Linux can be very finnicky between different setups. If you're experiencing any issues or it isn't working on your system, please confirm that you have all requirements, and if you do, please create an issue and I will try to resolve it.

Upon first startup, all Python dependencies will be installed into a venv. This might take some time, so expect first startup to take upwards of 30 seconds before you actually see the application. This is normal.

Resampling is required in Linux, creating a small delay when playing audio files. For me, it takes about a second when playing the first audio file, but then is not noticeable after the first sound.

# Requirements

## Windows
[VB Audio Cable](https://vb-audio.com/Cable/) (REQUIRED)

[Python 3.x.x](https://www.python.org/) (REQUIRED)

[VAC](https://vac.muzychenko.net/en/download.htm), or anything similar that lets you route output audio through an input device. (optional, only needed for the clipper)

[Audacity](https://www.audacityteam.org/download/) (optional, only needed for processing clips export via clipper)

[Friends](https://discord.gg/DKJBCxDvEw) (optional, you can also play the sounds for yourself)

## Linux
Python 3.x.x

Pipewire

Audacity (optional, only needed for editing and processing clips)

Discord/any chromium chat application -- currently for Linux, it detects "Chromium input" as the device to play audio through. I will add an option for this later, but at the moment it will only work with chromium chat applications

# Screenshots
![sc1](https://i.imgur.com/qC0eutm.png)
![sc2](https://i.imgur.com/lx7CPpL.png)
![sc3](https://i.imgur.com/nJV1yPj.png)
![sc4](https://i.imgur.com/nMqCJgb.png)

# NOTE
This project isn't finished. Currently there's no tutorials explaining how to install VB Audio Cable (REQUIRED TO USE SOFTWARE), or how to set up the clipper.

I plan to add a settings menu to configure devices as well, so you aren't forced to use VB, and will be able to just play it through your headphones/speakers if you would like. The code is pretty simple (and ugly), anyone can feel free to move the process along faster. I can't promise fast updates on tutorials unless this gains some traction, as I just made this primarily for me and my friends.

# Credits
[Godot Engine](https://github.com/godotengine/godot)
