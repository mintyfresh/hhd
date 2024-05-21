module platform.hhd.platform.win32.debug_;

debug: // DEBUG ONLY CODE

import core.sys.windows.windows;
import std.stdio;

/// See: hhd.platform.common.debugReadEntireFile
extern (System)
void[] debugReadEntireFile(const(char)* fileName) nothrow @nogc
{
    assert(fileName, "File name is null");

    HANDLE file = CreateFileA(
        fileName,
        GENERIC_READ,
        FILE_SHARE_READ,
        null,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        null
    );

    if (file == INVALID_HANDLE_VALUE)
    {
        debug writeln("Failed to open file: ", fileName);
        return null;
    }

    scope (exit)
    {
        CloseHandle(file);
    }

    LARGE_INTEGER rawFileSize;
    if (!GetFileSizeEx(file, &rawFileSize))
    {
        debug writeln("Failed to get file size: ", fileName);
        return null;
    }

    // TODO: Handle large files
    assert(rawFileSize.QuadPart <= DWORD.max, "File is too large (greater than 4GB)");
    DWORD fileSize = cast(DWORD) rawFileSize.QuadPart;

    void* fileMemory = VirtualAlloc(
        null,
        fileSize,
        MEM_RESERVE | MEM_COMMIT,
        PAGE_READWRITE
    );

    if (!fileMemory)
    {
        debug writefln("Failed to allocate memory for file: %s (%d bytes)", fileName, fileSize);
        return null;
    }

    DWORD bytesRead;
    if (!ReadFile(file, fileMemory, fileSize, &bytesRead, null) || bytesRead != fileSize)
    {
        debug writefln("Failed to read file: %s (%d bytes)", fileName, fileSize);
        VirtualFree(fileMemory, 0, MEM_RELEASE); // Free memory before returning

        return null;
    }

    return fileMemory[0..fileSize];
}

/// See: hhd.platform.common.debugWriteEntireFile
extern (System)
bool debugWriteEntireFile(const(char)* fileName, void[] buffer) nothrow @nogc
{
    assert(fileName, "File name is null");
    assert(buffer, "Buffer is null");

    HANDLE file = CreateFileA(
        fileName,
        GENERIC_WRITE,
        0,
        null,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        null
    );

    if (file == INVALID_HANDLE_VALUE)
    {
        debug writeln("Failed to create or open file: ", fileName);
        return false;
    }

    scope (exit)
    {
        CloseHandle(file);
    }

    DWORD bytesWritten;
    DWORD bytesToWrite = cast(DWORD) buffer.length;
    if (!WriteFile(file, buffer.ptr, bytesToWrite, &bytesWritten, null) || bytesWritten != bytesToWrite)
    {
        debug writefln("Failed to write file: %s (%d bytes)", fileName, buffer.length);
        return false;
    }

    return true;
}

/// See: hhd.platform.common.debugFreeFileMemory
extern (System)
bool debugFreeFileMemory(void[] memory) nothrow @nogc
{
    return VirtualFree(memory.ptr, 0, MEM_RELEASE) != 0;
}
