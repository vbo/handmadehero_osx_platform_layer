# OS X Platform Layer for Handmade Hero

[Handmade Hero](https://handmadehero.org/) is an amazing project by Casey Muratori where he is creating a complete,
professional-quality game entirely from scratch: no libraries, no engine etc.
Project is accompanied by videos that explain every single line of source code.

The game implementation consists of two separated parts: platform-independent game code and a platform layer.
Casey for now only provides a platform layer for Windows (implemented from scratch, using WinAPI, XInput, DirectSound etc)
so if someone wants to follow along on other platforms they need at least partially implemented platform layer for their platform.

I am following along on OS X so I've decided to implement a native OS X platform layer for myself.
My goal here is to implement a full-featured platform layer which is fully compatible with game sources
so I can just download the new version, copy my files over it and launch the whole thing on OS X.

In the mood of Handmade Hero I am trying to make my platform layer as minimalistic and as handmade as possible. E.g. I am not
using XCode and just have a simple bash script as my "build system". I am not using Interface Builder and other stuff.
Basically the whole platform layer is just one file that can be read through like a blog-post with comments
on every decision I made.

So far I've implemented everything required to launch any version of the game starting from day 29
(when Casey finished working on Windows platform layer). Please post an issue if you have any problems.

Here is a list of features:

 - Native Cocoa window
 - OS events handling
 - High-resolution timing
 - OpenGL-based bitmap render with vSync support
 - Keyboard input support (using OS events)
 - Gamepad input support (using IOKit IOHIDManager, up to 4 gamepads)
 - CoreAudio-based sound
 - Debug file I/O
 - Dynamic game code loading with hot-reload support
 - Input recording and looped playback
 - Overlay semi-transparent window support
 - Memory allocation
 - Handcoded application bundle

There are several TODOs in code, but for me this platform layer works like a charm =)

## Installation

 - Download game source package from Handmade Hero (you need to pre-order the game first!)
 - Unzip source for the day you are at
 - Merge platform layer files with unzipped source (in Finder just copy directories over and click "merge")
 - Use ./code/osx_build.sh to build and ../build/osx_handmade.out to launch the game
 - If there are some minor bugs - just fix them =)
