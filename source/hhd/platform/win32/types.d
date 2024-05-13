module hhd.platform.win32.types;

import core.sys.windows.windows;
import hhd.util.types;

struct Win32SoundOutput
{
    int sampleRate;
    int bytesPerSample;
    DWORD secondaryBufferSize;

    int latencyInSamples;
    uint currentSampleIndex;

    @property
    enum ushort CHANNELS_COUNT = 2; 
}

struct Win32OffscreenBuffer
{
    BITMAPINFO info;
    void* memory;

    @property
    enum LONG BYTES_PER_PIXEL = 4;

    @property
    pragma(inline, true)
    LONG width() const nothrow @nogc
    {
        return info.bmiHeader.biWidth;
    }

    @property
    pragma(inline, true)
    LONG height() const nothrow @nogc
    {
        return -info.bmiHeader.biHeight;
    }

    @property
    pragma(inline, true)
    LONG pitch() const nothrow @nogc
    {
        return width * BYTES_PER_PIXEL;
    }

    @property
    pragma(inline, true)
    size_t memorySize() const nothrow @nogc
    {
        return width * height * BYTES_PER_PIXEL;
    }
}

struct Win32WindowDimensions
{
    LONG width;
    LONG height;

    /// Returns the dimensions as a compile-time tuple.
    /// Returns: (width, height)
    @property
    alias tuple = AliasSeq!(this.width, this.height);
}

struct Win32ControllerButtonMapping
{
    import hhd.platform.common : GameButton;

    GameButton gameButton;
    DWORD xInputButton;

    @disable this();
}
