module hhd.platform.win32.direct_sound;

import core.sys.windows.windows;

struct DSCAPS
{
    DWORD dwSize;
    DWORD dwFlags;
    DWORD dwMinSecondarySampleRate;
    DWORD dwMaxSecondarySampleRate;
    DWORD dwPrimaryBuffers;
    DWORD dwMaxHwMixingAllBuffers;
    DWORD dwMaxHwMixingStaticBuffers;
    DWORD dwMaxHwMixingStreamingBuffers;
    DWORD dwFreeHwMixingAllBuffers;
    DWORD dwFreeHwMixingStaticBuffers;
    DWORD dwFreeHwMixingStreamingBuffers;
    DWORD dwMaxHw3DAllBuffers;
    DWORD dwMaxHw3DStaticBuffers;
    DWORD dwMaxHw3DStreamingBuffers;
    DWORD dwFreeHw3DAllBuffers;
    DWORD dwFreeHw3DStaticBuffers;
    DWORD dwFreeHw3DStreamingBuffers;
    DWORD dwTotalHwMemBytes;
    DWORD dwFreeHwMemBytes;
    DWORD dwMaxContigFreeHwMemBytes;
    DWORD dwUnlockTransferRateHwBuffers;
    DWORD dwPlayCpuOverheadSwBuffers;
    DWORD dwReserved1;
    DWORD dwReserved2;
}

alias LPDSCAPS = DSCAPS*;
alias LPCDSCAPS = const DSCAPS*;

struct DSBCAPS
{
    DWORD dwSize;
    DWORD dwFlags;
    DWORD dwBufferBytes;
    DWORD dwUnlockTransferRate;
    DWORD dwPlayCpuOverhead;
}

alias LPDSBCAPS = DSBCAPS*;
alias LPCDSBCAPS = const DSBCAPS*;

struct DSBUFFERDESC
{
    DWORD dwSize;
    DWORD dwFlags;
    DWORD dwBufferBytes;
    DWORD dwReserved;
    LPWAVEFORMATEX lpwfxFormat;
    GUID guid3DAlgorithm;
}

alias LPDSBUFFERDESC = DSBUFFERDESC*;
alias LPCDSBUFFERDESC = const DSBUFFERDESC*;

enum : DWORD
{
    DSSCL_NORMAL       = 0x00000001,
    DSSCL_PRIORITY     = 0x00000002,
    DSSCL_EXCLUSIVE    = 0x00000003,
    DSSCL_WRITEPRIMARY = 0x00000004,
}

enum : DWORD
{
    DSBCAPS_PRIMARYBUFFER       = 0x00000001,
    DSBCAPS_STATIC              = 0x00000002,
    DSBCAPS_LOCHARDWARE         = 0x00000004,
    DSBCAPS_LOCSOFTWARE         = 0x00000008,
    DSBCAPS_CTRL3D              = 0x00000010,
    DSBCAPS_CTRLFREQUENCY       = 0x00000020,
    DSBCAPS_CTRLPAN             = 0x00000040,
    DSBCAPS_CTRLVOLUME          = 0x00000080,
    DSBCAPS_CTRLPOSITIONNOTIFY  = 0x00000100,
    DSBCAPS_CTRLFX              = 0x00000200,
    DSBCAPS_STICKYFOCUS         = 0x00004000,
    DSBCAPS_GLOBALFOCUS         = 0x00008000,
    DSBCAPS_GETCURRENTPOSITION2 = 0x00010000,
    DSBCAPS_MUTE3DATMAXDISTANCE = 0x00020000,
    DSBCAPS_LOCDEFER            = 0x00040000,
    DSBCAPS_TRUEPLAYPOSITION    = 0x00080000,
}

mixin template COMVTable(Interface)
{
    alias STDMETHOD(TList...) = extern (Windows) HRESULT function(Interface*, TList) nothrow @nogc;
    alias STDMETHOD_(TList...) = extern (Windows) ULONG function(Interface*, TList) nothrow @nogc;

    STDMETHOD!(REFIID, void**) pQueryInterface;
    STDMETHOD_!() pAddRef;
    STDMETHOD_!() pRelease;
}

extern (Windows) struct IDirectSound
{
    struct VTable
    {
        mixin COMVTable!(IDirectSound);

        STDMETHOD!(LPCDSBUFFERDESC, LPDIRECTSOUNDBUFFER*, LPUNKNOWN) pCreateSoundBuffer;
        STDMETHOD!(LPDSCAPS) pGetCaps;
        STDMETHOD!(LPDIRECTSOUNDBUFFER, LPDIRECTSOUNDBUFFER*) pDuplicateSoundBuffer;
        STDMETHOD!(HWND, DWORD) pSetCooperativeLevel;
        STDMETHOD!() pCompact;
        STDMETHOD!(LPDWORD) pGetSpeakerConfig;
        STDMETHOD!(DWORD) pSetSpeakerConfig;
        STDMETHOD!(LPCGUID) pInitialize;
    }

    VTable* lpVtbl;

    auto opDispatch(string op, TList...)(TList args)
        if (__traits(hasMember, VTable, "p" ~ op))
    {
        return __traits(getMember, lpVtbl, "p" ~ op)(&this, args);
    }
}

alias LPDIRECTSOUND = IDirectSound*;
alias LPCDIRECTSOUND = const IDirectSound*;

extern (Windows) struct IDirectSoundBuffer
{
    struct VTable
    {
        mixin COMVTable!(IDirectSoundBuffer);

        STDMETHOD!(LPDSBCAPS) pGetCaps;
        STDMETHOD!(LPDWORD, LPDWORD) pGetCurrentPosition;
        STDMETHOD!(LPWAVEFORMATEX, DWORD, LPDWORD) pGetFormat;
        STDMETHOD!(LPLONG) pGetVolume;
        STDMETHOD!(LPLONG) pGetPan;
        STDMETHOD!(LPDWORD) pGetFrequency;
        STDMETHOD!(LPDWORD) pGetStatus;
        STDMETHOD!(LPDIRECTSOUND, LPCDSBUFFERDESC) pInitialize;
        STDMETHOD!(DWORD, DWORD, LPVOID*, LPDWORD, LPVOID*, LPDWORD, DWORD) pLock;
        STDMETHOD!(DWORD, DWORD, DWORD) pPlay;
        STDMETHOD!(DWORD) pSetCurrentPosition;
        STDMETHOD!(LPCWAVEFORMATEX) pSetFormat;
        STDMETHOD!(LONG) pSetVolume;
        STDMETHOD!(LONG) pSetPan;
        STDMETHOD!(DWORD) pSetFrequency;
        STDMETHOD!() pStop;
        STDMETHOD!(LPVOID, DWORD, LPVOID, DWORD) pUnlock;
        STDMETHOD!() pRestore;
    }

    VTable* lpVtbl;

    auto opDispatch(string op, TList...)(TList args)
        if (__traits(hasMember, VTable, "p" ~ op))
    {
        return __traits(getMember, lpVtbl, "p" ~ op)(&this, args);
    }
}

alias LPDIRECTSOUNDBUFFER = IDirectSoundBuffer*;
alias LPCDIRECTSOUNDBUFFER = const IDirectSoundBuffer*;

extern (Windows) nothrow @nogc
{
    alias procDirectSoundCreate = HRESULT function(LPGUID pcGuidDevice, LPDIRECTSOUND* ppDS, LPUNKNOWN pUnkOuter);
}

