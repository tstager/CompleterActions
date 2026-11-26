using System;
using System.Buffers.Binary;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace CompleterActions.Internal;

/// <summary>
/// Reads the target of a Windows app execution alias: the zero-byte reparse point with the tag
/// <c>IO_REPARSE_TAG_APPEXECLINK</c> that a packaged app places on <c>PATH</c>. No managed API
/// gives that target, so the reparse data is read with <c>CreateFileW</c> and
/// <c>DeviceIoControl</c>. Nothing is called on Linux or macOS.
/// </summary>
public static class AppExecutionAlias
{
    private const uint AppExecLinkTag = 0x8000001B;
    private const uint FileReadAttributes = 0x0080;
    private const uint FileShareAll = 0x0007;
    private const uint OpenExisting = 3;
    private const uint FileFlagOpenReparsePoint = 0x00200000;
    private const uint FileFlagBackupSemantics = 0x02000000;
    private const uint FsctlGetReparsePoint = 0x000900A8;
    private const int ReparseBufferSize = 16384;
    private const int HeaderSize = 8;
    private const int VersionSize = 4;
    private const int TargetStringIndex = 2;

    /// <summary>
    /// Reads the target executable an app execution alias names: the third NUL-terminated UTF-16
    /// string of its reparse data, after the 32-bit version, the package family name, and the
    /// application user model ID. The version is not checked.
    /// </summary>
    /// <param name="path">The full path of the file to read.</param>
    /// <returns>
    /// <see langword="null"/> when the process is not on Windows, or when the file is not an
    /// <c>APPEXECLINK</c> reparse point or its reparse data cannot be read; the empty string when
    /// it is one whose data holds no third string; otherwise the target path as the data gives it.
    /// </returns>
    /// <exception cref="ArgumentException"><paramref name="path"/> is null or empty.</exception>
    public static string? GetTarget(string path)
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        ArgumentException.ThrowIfNullOrEmpty(path);

        byte[] buffer = new byte[ReparseBufferSize];
        uint count;

        using (SafeFileHandle handle = CreateFileW(path, FileReadAttributes, FileShareAll, IntPtr.Zero, OpenExisting, FileFlagOpenReparsePoint | FileFlagBackupSemantics, IntPtr.Zero))
        {
            if (handle.IsInvalid)
            {
                return null;
            }

            if (!DeviceIoControl(handle, FsctlGetReparsePoint, IntPtr.Zero, 0, buffer, (uint)buffer.Length, out count, IntPtr.Zero))
            {
                return null;
            }
        }

        if (count < HeaderSize || BinaryPrimitives.ReadUInt32LittleEndian(buffer) != AppExecLinkTag)
        {
            return null;
        }

        int dataLength = BinaryPrimitives.ReadUInt16LittleEndian(buffer.AsSpan(4));
        int end = Math.Min((int)count, HeaderSize + dataLength);
        int offset = HeaderSize + VersionSize;

        for (int index = 0; index <= TargetStringIndex; index++)
        {
            int terminator = FindTerminator(buffer, offset, end);
            if (terminator < 0)
            {
                return string.Empty;
            }

            if (index == TargetStringIndex)
            {
                return Encoding.Unicode.GetString(buffer, offset, terminator - offset);
            }

            offset = terminator + 2;
        }

        return string.Empty;
    }

    private static int FindTerminator(byte[] buffer, int offset, int end)
    {
        for (int position = offset; position + 1 < end; position += 2)
        {
            if (buffer[position] == 0 && buffer[position + 1] == 0)
            {
                return position;
            }
        }

        return -1;
    }

    [SupportedOSPlatform("windows")]
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [SupportedOSPlatform("windows")]
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeviceIoControl(SafeFileHandle hDevice, uint dwIoControlCode, IntPtr lpInBuffer, uint nInBufferSize, [Out] byte[] lpOutBuffer, uint nOutBufferSize, out uint lpBytesReturned, IntPtr lpOverlapped);
}
