module hhd.platform.common;

struct GameOffscreenBuffer
{
    void* memory; // NOTE: Pixels are always 32-bits wide, Memory Order BB GG RR XX

    int width;
    int height;
    int pitch;
}

struct GameSoundOutputBuffer
{
    short* samples;

    int sampleRate;
    int sampleCount;
}

extern (System) void gameOutputSound(in ref GameSoundOutputBuffer soundBuffer, int toneHz) nothrow @nogc;
extern (System) void gameUpdateAndRender(in ref GameOffscreenBuffer buffer, int xOffset, int yOffset) nothrow @nogc;
