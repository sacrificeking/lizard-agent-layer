using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Lizard.AgentLayer.Native
{
    public sealed class WindowsFileMetadata
    {
        internal WindowsFileMetadata(long length, long lastWriteUtcTicks, uint volumeSerial, ulong fileId)
        {
            Length = length;
            LastWriteUtcTicks = lastWriteUtcTicks;
            VolumeSerial = volumeSerial;
            FileId = fileId;
        }

        public long Length { get; private set; }
        public long LastWriteUtcTicks { get; private set; }
        public uint VolumeSerial { get; private set; }
        public ulong FileId { get; private set; }
    }

    public sealed class WindowsRootIdentity
    {
        internal WindowsRootIdentity(uint volumeSerial, ulong fileId)
        {
            VolumeSerial = volumeSerial;
            FileId = fileId;
        }

        public uint VolumeSerial { get; private set; }
        public ulong FileId { get; private set; }
    }

    internal static class WindowsNativeFs
    {
        internal const uint GenericRead = 0x80000000;
        internal const uint GenericWrite = 0x40000000;
        internal const uint Delete = 0x00010000;
        internal const uint FileReadAttributes = 0x00000080;
        internal const uint FileTraverse = 0x00000020;
        internal const uint ShareRead = 0x00000001;
        internal const uint ShareWrite = 0x00000002;
        internal const uint ShareDelete = 0x00000004;
        internal const uint CreateNew = 1;
        internal const uint OpenExisting = 3;
        internal const uint FileAttributeNormal = 0x00000080;
        internal const uint FileAttributeDirectory = 0x00000010;
        internal const uint FileAttributeReparsePoint = 0x00000400;
        internal const uint FileFlagOpenReparsePoint = 0x00200000;
        internal const uint FileFlagBackupSemantics = 0x02000000;
        internal const uint Synchronize = 0x00100000;
        internal const uint NativeFileOpen = 1;
        internal const uint NativeFileCreate = 2;
        internal const uint NativeFileOpenIf = 3;
        internal const uint NativeFileDirectoryFile = 0x00000001;
        internal const uint NativeFileSynchronousIoNonAlert = 0x00000020;
        internal const uint NativeFileNonDirectoryFile = 0x00000040;
        internal const uint NativeFileOpenReparsePoint = 0x00200000;
        internal const uint ObjectCaseInsensitive = 0x00000040;
        internal const uint ObjectDontReparse = 0x00001000;
        internal const int FileRenameInfo = 3;
        internal const int FileDispositionInfo = 4;
        internal const int NativeFileRenameInformation = 10;

        [StructLayout(LayoutKind.Sequential)]
        internal struct ByHandleFileInformation
        {
            internal uint FileAttributes;
            internal System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            internal System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            internal System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            internal uint VolumeSerialNumber;
            internal uint FileSizeHigh;
            internal uint FileSizeLow;
            internal uint NumberOfLinks;
            internal uint FileIndexHigh;
            internal uint FileIndexLow;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct IoStatusBlock
        {
            internal IntPtr Status;
            internal UIntPtr Information;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct UnicodeString
        {
            internal ushort Length;
            internal ushort MaximumLength;
            internal IntPtr Buffer;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct ObjectAttributes
        {
            internal uint Length;
            internal IntPtr RootDirectory;
            internal IntPtr ObjectName;
            internal uint Attributes;
            internal IntPtr SecurityDescriptor;
            internal IntPtr SecurityQualityOfService;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern SafeFileHandle CreateFileW(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetFileInformationByHandle(
            SafeFileHandle file,
            out ByHandleFileInformation information);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool WriteFile(
            SafeFileHandle file,
            byte[] buffer,
            uint bytesToWrite,
            out uint bytesWritten,
            IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool ReadFile(
            SafeFileHandle file,
            byte[] buffer,
            uint bytesToRead,
            out uint bytesRead,
            IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool FlushFileBuffers(SafeFileHandle file);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetFileInformationByHandle(
            SafeFileHandle file,
            int informationClass,
            IntPtr information,
            uint bufferSize);

        [DllImport("ntdll.dll")]
        internal static extern int NtSetInformationFile(
            SafeFileHandle file,
            out IoStatusBlock ioStatusBlock,
            IntPtr information,
            uint length,
            int informationClass);

        [DllImport("ntdll.dll")]
        internal static extern int NtCreateFile(
            out IntPtr fileHandle,
            uint desiredAccess,
            ref ObjectAttributes objectAttributes,
            out IoStatusBlock ioStatusBlock,
            IntPtr allocationSize,
            uint fileAttributes,
            uint shareAccess,
            uint createDisposition,
            uint createOptions,
            IntPtr eaBuffer,
            uint eaLength);

        [DllImport("ntdll.dll")]
        internal static extern uint RtlNtStatusToDosError(uint status);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CreateDirectoryW(string path, IntPtr securityAttributes);

        internal static Exception NativeFailure(string operation, string path)
        {
            int error = Marshal.GetLastWin32Error();
            return new Win32Exception(error, "SAFEFS_NATIVE_CALL_FAILED: " + operation + " failed for " + path + " (win32=" + error.ToString(CultureInfo.InvariantCulture) + ")");
        }

        internal static Win32Exception NativeStatusFailure(string operation, string path, int status)
        {
            uint error = RtlNtStatusToDosError((uint)status);
            return new Win32Exception((int)error, "SAFEFS_NATIVE_CALL_FAILED: " + operation + " failed for " + path);
        }

        internal static SafeFileHandle OpenRelative(
            SafeFileHandle parent,
            string leaf,
            string displayPath,
            uint desiredAccess,
            uint createDisposition,
            uint createOptions,
            uint fileAttributes)
        {
            if (String.IsNullOrWhiteSpace(leaf) || leaf == "." || leaf == ".." || leaf.IndexOfAny(new char[] { '\\', '/', '\0' }) >= 0)
                throw new UnauthorizedAccessException("SAFEFS_INVALID_SEGMENT: Invalid relative path segment: " + leaf);

            IntPtr text = IntPtr.Zero;
            IntPtr unicodePointer = IntPtr.Zero;
            try
            {
                text = Marshal.StringToHGlobalUni(leaf);
                int byteLength = checked(leaf.Length * 2);
                UnicodeString unicode = new UnicodeString();
                unicode.Length = checked((ushort)byteLength);
                unicode.MaximumLength = checked((ushort)(byteLength + 2));
                unicode.Buffer = text;
                unicodePointer = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UnicodeString)));
                Marshal.StructureToPtr(unicode, unicodePointer, false);

                ObjectAttributes attributes = new ObjectAttributes();
                attributes.Length = (uint)Marshal.SizeOf(typeof(ObjectAttributes));
                attributes.RootDirectory = parent.DangerousGetHandle();
                attributes.ObjectName = unicodePointer;
                attributes.Attributes = ObjectCaseInsensitive | ObjectDontReparse;
                attributes.SecurityDescriptor = IntPtr.Zero;
                attributes.SecurityQualityOfService = IntPtr.Zero;

                IntPtr rawHandle;
                IoStatusBlock ioStatus;
                int status = NtCreateFile(
                    out rawHandle,
                    desiredAccess | Synchronize,
                    ref attributes,
                    out ioStatus,
                    IntPtr.Zero,
                    fileAttributes,
                    ShareRead | ShareWrite | ShareDelete,
                    createDisposition,
                    createOptions | NativeFileSynchronousIoNonAlert | NativeFileOpenReparsePoint,
                    IntPtr.Zero,
                    0);
                if (status < 0) throw NativeStatusFailure("NtCreateFile", displayPath, status);
                return new SafeFileHandle(rawHandle, true);
            }
            finally
            {
                if (unicodePointer != IntPtr.Zero) Marshal.FreeHGlobal(unicodePointer);
                if (text != IntPtr.Zero) Marshal.FreeHGlobal(text);
            }
        }

        internal static ByHandleFileInformation GetInformation(SafeFileHandle handle, string path)
        {
            ByHandleFileInformation information;
            if (!GetFileInformationByHandle(handle, out information))
                throw NativeFailure("GetFileInformationByHandle", path);
            return information;
        }

        internal static void ValidateDirectory(SafeFileHandle handle, string path, uint expectedVolume)
        {
            ByHandleFileInformation information = GetInformation(handle, path);
            if ((information.FileAttributes & FileAttributeReparsePoint) != 0)
                throw new UnauthorizedAccessException("SAFEFS_REPARSE_POINT: Linked directory is not allowed: " + path);
            if ((information.FileAttributes & FileAttributeDirectory) == 0)
                throw new UnauthorizedAccessException("SAFEFS_NOT_DIRECTORY: Expected a directory: " + path);
            if (information.VolumeSerialNumber != expectedVolume)
                throw new UnauthorizedAccessException("SAFEFS_DEVICE_BOUNDARY: Directory crosses the authorized volume: " + path);
        }

        internal static void ValidateOrdinaryFile(SafeFileHandle handle, string path, uint expectedVolume)
        {
            ByHandleFileInformation information = GetInformation(handle, path);
            if ((information.FileAttributes & FileAttributeReparsePoint) != 0 || information.NumberOfLinks > 1)
                throw new UnauthorizedAccessException("SAFEFS_REPARSE_POINT: Linked terminal file is not allowed: " + path);
            if ((information.FileAttributes & FileAttributeDirectory) != 0)
                throw new UnauthorizedAccessException("SAFEFS_NOT_FILE: Expected an ordinary file: " + path);
            if (information.VolumeSerialNumber != expectedVolume)
                throw new UnauthorizedAccessException("SAFEFS_DEVICE_BOUNDARY: File crosses the authorized volume: " + path);
        }

        internal static SafeFileHandle OpenDirectory(string path, uint expectedVolume)
        {
            SafeFileHandle handle = CreateFileW(
                path,
                FileTraverse | FileReadAttributes | Synchronize,
                ShareRead | ShareWrite | ShareDelete,
                IntPtr.Zero,
                OpenExisting,
                FileFlagBackupSemantics | FileFlagOpenReparsePoint,
                IntPtr.Zero);
            if (handle.IsInvalid)
            {
                handle.Dispose();
                throw NativeFailure("CreateFileW(directory)", path);
            }
            try
            {
                ValidateDirectory(handle, path, expectedVolume);
                return handle;
            }
            catch
            {
                handle.Dispose();
                throw;
            }
        }

        internal static SafeFileHandle OpenRelativeDirectory(SafeFileHandle parent, string leaf, string path, uint expectedVolume, uint disposition)
        {
            SafeFileHandle handle = OpenRelative(
                parent,
                leaf,
                path,
                FileTraverse | FileReadAttributes | Synchronize,
                disposition,
                NativeFileDirectoryFile,
                FileAttributeDirectory);
            try
            {
                ValidateDirectory(handle, path, expectedVolume);
                return handle;
            }
            catch
            {
                handle.Dispose();
                throw;
            }
        }

        internal static SafeFileHandle OpenVolumeRoot(string path, out uint volumeSerial)
        {
            SafeFileHandle handle = CreateFileW(
                path,
                GenericRead | FileReadAttributes,
                ShareRead | ShareWrite | ShareDelete,
                IntPtr.Zero,
                OpenExisting,
                FileFlagBackupSemantics | FileFlagOpenReparsePoint,
                IntPtr.Zero);
            if (handle.IsInvalid)
            {
                handle.Dispose();
                throw NativeFailure("CreateFileW(volume root)", path);
            }
            ByHandleFileInformation information = GetInformation(handle, path);
            volumeSerial = information.VolumeSerialNumber;
            ValidateDirectory(handle, path, volumeSerial);
            return handle;
        }

        internal static string[] SegmentsBelowVolume(string fullPath, string volumeRoot)
        {
            string relative = fullPath.Substring(volumeRoot.Length).Trim(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (relative.Length == 0) return new string[0];
            return relative.Split(new char[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar }, StringSplitOptions.RemoveEmptyEntries);
        }

        internal static void AssertContained(string root, string destination)
        {
            string prefix = root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (!destination.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                throw new UnauthorizedAccessException("SAFEFS_OUTSIDE_ROOT: Destination escapes the authorized root: " + destination);
        }

        internal static void WriteAll(SafeFileHandle handle, byte[] value, string path)
        {
            int offset = 0;
            while (offset < value.Length)
            {
                int count = Math.Min(value.Length - offset, 1024 * 1024);
                byte[] chunk;
                if (offset == 0 && count == value.Length) chunk = value;
                else
                {
                    chunk = new byte[count];
                    Buffer.BlockCopy(value, offset, chunk, 0, count);
                }
                uint written;
                if (!WriteFile(handle, chunk, (uint)count, out written, IntPtr.Zero))
                    throw NativeFailure("WriteFile", path);
                if (written == 0) throw new IOException("SAFEFS_NATIVE_CALL_FAILED: WriteFile made no progress for " + path);
                offset += (int)written;
            }
        }

        internal static byte[] ReadAll(SafeFileHandle handle, string path)
        {
            return ReadAll(handle, path, Int32.MaxValue);
        }

        internal static byte[] ReadAll(SafeFileHandle handle, string path, long maximumBytes)
        {
            ByHandleFileInformation information = GetInformation(handle, path);
            long length = ((long)information.FileSizeHigh << 32) | information.FileSizeLow;
            if (length > Int32.MaxValue || length > maximumBytes)
                throw new IOException("SAFEFS_FILE_TOO_LARGE: Protected file exceeds the supported in-memory size: " + path);
            byte[] result = new byte[(int)length];
            int offset = 0;
            while (offset < result.Length)
            {
                int count = Math.Min(result.Length - offset, 1024 * 1024);
                byte[] chunk = new byte[count];
                uint read;
                if (!ReadFile(handle, chunk, (uint)count, out read, IntPtr.Zero))
                    throw NativeFailure("ReadFile", path);
                if (read == 0) break;
                Buffer.BlockCopy(chunk, 0, result, offset, (int)read);
                offset += (int)read;
            }
            if (offset != result.Length)
                throw new IOException("SAFEFS_CHANGED_DURING_READ: File length changed during protected read: " + path);
            return result;
        }
    }

    public sealed class WindowsDirectoryLease : IDisposable
    {
        private readonly List<SafeFileHandle> handles;
        private readonly SafeFileHandle parentHandle;
        private readonly uint volumeSerial;
        private bool disposed;

        internal WindowsDirectoryLease(List<SafeFileHandle> openHandles, SafeFileHandle parent, uint volume, string root, string destination)
        {
            handles = openHandles;
            parentHandle = parent;
            volumeSerial = volume;
            AuthorizedRoot = root;
            DestinationPath = destination;
            ParentPath = Path.GetDirectoryName(destination);
            LeafName = Path.GetFileName(destination);
        }

        public string AuthorizedRoot { get; private set; }
        public string DestinationPath { get; private set; }
        public string ParentPath { get; private set; }
        public string LeafName { get; private set; }
        public uint VolumeSerial { get { return volumeSerial; } }

        private void AssertActive()
        {
            if (disposed) throw new ObjectDisposedException("WindowsDirectoryLease");
        }

        private SafeFileHandle OpenExistingFile(uint access)
        {
            AssertActive();
            SafeFileHandle handle;
            try
            {
                handle = WindowsNativeFs.OpenRelative(
                    parentHandle,
                    LeafName,
                    DestinationPath,
                    access | WindowsNativeFs.FileReadAttributes,
                    WindowsNativeFs.NativeFileOpen,
                    0,
                    WindowsNativeFs.FileAttributeNormal);
            }
            catch (Win32Exception error)
            {
                if (error.NativeErrorCode == 2 || error.NativeErrorCode == 3)
                    throw new FileNotFoundException("SAFEFS_FILE_MISSING: File does not exist: " + DestinationPath, error);
                throw;
            }
            try
            {
                WindowsNativeFs.ValidateOrdinaryFile(handle, DestinationPath, volumeSerial);
                return handle;
            }
            catch
            {
                handle.Dispose();
                throw;
            }
        }

        private SafeFileHandle OpenExistingDirectory()
        {
            AssertActive();
            try
            {
                return WindowsNativeFs.OpenRelativeDirectory(
                    parentHandle,
                    LeafName,
                    DestinationPath,
                    volumeSerial,
                    WindowsNativeFs.NativeFileOpen);
            }
            catch (Win32Exception error)
            {
                if (error.NativeErrorCode == 2 || error.NativeErrorCode == 3)
                    throw new DirectoryNotFoundException("SAFEFS_DIRECTORY_MISSING: Directory does not exist: " + DestinationPath);
                throw;
            }
        }

        public byte[] ReadExisting()
        {
            using (SafeFileHandle handle = OpenExistingFile(WindowsNativeFs.GenericRead))
                return WindowsNativeFs.ReadAll(handle, DestinationPath);
        }

        public byte[] ReadExisting(long maximumBytes)
        {
            using (SafeFileHandle handle = OpenExistingFile(WindowsNativeFs.GenericRead))
                return WindowsNativeFs.ReadAll(handle, DestinationPath, maximumBytes);
        }

        public WindowsFileMetadata GetExistingMetadata()
        {
            using (SafeFileHandle handle = OpenExistingFile(0))
            {
                WindowsNativeFs.ByHandleFileInformation information = WindowsNativeFs.GetInformation(handle, DestinationPath);
                long length = ((long)information.FileSizeHigh << 32) | information.FileSizeLow;
                long fileTime = ((long)(uint)information.LastWriteTime.dwHighDateTime << 32) | (uint)information.LastWriteTime.dwLowDateTime;
                ulong fileId = ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow;
                return new WindowsFileMetadata(length, DateTime.FromFileTimeUtc(fileTime).Ticks, information.VolumeSerialNumber, fileId);
            }
        }

        public WindowsFileMetadata GetExistingDirectoryMetadata()
        {
            using (SafeFileHandle handle = OpenExistingDirectory())
            {
                WindowsNativeFs.ByHandleFileInformation information = WindowsNativeFs.GetInformation(handle, DestinationPath);
                long fileTime = ((long)(uint)information.LastWriteTime.dwHighDateTime << 32) | (uint)information.LastWriteTime.dwLowDateTime;
                ulong fileId = ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow;
                return new WindowsFileMetadata(0, DateTime.FromFileTimeUtc(fileTime).Ticks, information.VolumeSerialNumber, fileId);
            }
        }

        public void AssertExistingDestinationSafe()
        {
            try
            {
                using (SafeFileHandle handle = OpenExistingFile(0)) { }
            }
            catch (FileNotFoundException) { return; }
            catch (Win32Exception error)
            {
                if (error.NativeErrorCode == 2 || error.NativeErrorCode == 3) return;
                throw;
            }
        }

        private void MarkDelete(SafeFileHandle handle, string path)
        {
            IntPtr buffer = Marshal.AllocHGlobal(1);
            try
            {
                Marshal.WriteByte(buffer, 1);
                if (!WindowsNativeFs.SetFileInformationByHandle(handle, WindowsNativeFs.FileDispositionInfo, buffer, 1))
                    throw WindowsNativeFs.NativeFailure("SetFileInformationByHandle(disposition)", path);
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        private void RenameStage(SafeFileHandle stage, bool replace)
        {
            byte[] nameBytes = System.Text.Encoding.Unicode.GetBytes(LeafName);
            int rootOffset = IntPtr.Size == 8 ? 8 : 4;
            int lengthOffset = rootOffset + IntPtr.Size;
            int nameOffset = lengthOffset + 4;
            int total = nameOffset + nameBytes.Length;
            IntPtr buffer = Marshal.AllocHGlobal(total);
            try
            {
                for (int i = 0; i < total; i++) Marshal.WriteByte(buffer, i, 0);
                Marshal.WriteByte(buffer, 0, replace ? (byte)1 : (byte)0);
                Marshal.WriteIntPtr(buffer, rootOffset, parentHandle.DangerousGetHandle());
                Marshal.WriteInt32(buffer, lengthOffset, nameBytes.Length);
                Marshal.Copy(nameBytes, 0, new IntPtr(buffer.ToInt64() + nameOffset), nameBytes.Length);
                WindowsNativeFs.IoStatusBlock ioStatus;
                int status = 0;
                for (int attempt = 0; attempt < 5; attempt++)
                {
                    status = WindowsNativeFs.NtSetInformationFile(stage, out ioStatus, buffer, (uint)total, WindowsNativeFs.NativeFileRenameInformation);
                    if (status >= 0) break;
                    if (attempt < 4) System.Threading.Thread.Sleep(10 * (attempt + 1));
                }
                if (status < 0)
                {
                    uint error = WindowsNativeFs.RtlNtStatusToDosError((uint)status);
                    throw new Win32Exception((int)error, "SAFEFS_NATIVE_CALL_FAILED: NtSetInformationFile(rename) failed for " + DestinationPath);
                }
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        public void WriteAtomic(byte[] value, bool replace)
        {
            AssertActive();
            if (replace) AssertExistingDestinationSafe();
            string stageName = ".lizard-stage-" + Guid.NewGuid().ToString("N") + ".tmp";
            string stagePath = Path.Combine(ParentPath, stageName);
            SafeFileHandle stage = WindowsNativeFs.OpenRelative(
                parentHandle,
                stageName,
                stagePath,
                WindowsNativeFs.GenericWrite | WindowsNativeFs.Delete | WindowsNativeFs.FileReadAttributes,
                WindowsNativeFs.NativeFileCreate,
                WindowsNativeFs.NativeFileNonDirectoryFile,
                WindowsNativeFs.FileAttributeNormal);
            bool renamed = false;
            try
            {
                WindowsNativeFs.ValidateOrdinaryFile(stage, stagePath, volumeSerial);
                WindowsNativeFs.WriteAll(stage, value, stagePath);
                if (!WindowsNativeFs.FlushFileBuffers(stage))
                    throw WindowsNativeFs.NativeFailure("FlushFileBuffers", stagePath);
                RenameStage(stage, replace);
                renamed = true;
            }
            finally
            {
                if (!renamed && !stage.IsInvalid && !stage.IsClosed)
                {
                    try { MarkDelete(stage, stagePath); } catch { }
                }
                stage.Dispose();
            }
        }

        public void RemoveFile()
        {
            using (SafeFileHandle handle = OpenExistingFile(WindowsNativeFs.Delete))
                MarkDelete(handle, DestinationPath);
        }

        public void RemoveFileChecked(string expectedVolumeId, string expectedFileId)
        {
            uint expectedVolume = Convert.ToUInt32(expectedVolumeId, 16);
            ulong expectedFile = Convert.ToUInt64(expectedFileId, 16);
            using (SafeFileHandle handle = OpenExistingFile(WindowsNativeFs.Delete))
            {
                WindowsNativeFs.ByHandleFileInformation information = WindowsNativeFs.GetInformation(handle, DestinationPath);
                ulong fileId = ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow;
                if (information.VolumeSerialNumber != expectedVolume || fileId != expectedFile)
                    throw new UnauthorizedAccessException("SAFEFS_IDENTITY_MISMATCH: Removal target identity changed: " + DestinationPath);
                MarkDelete(handle, DestinationPath);
            }
        }

        public void RemoveEmptyDirectory()
        {
            AssertActive();
            SafeFileHandle handle = WindowsNativeFs.OpenRelative(
                parentHandle,
                LeafName,
                DestinationPath,
                WindowsNativeFs.Delete | WindowsNativeFs.FileReadAttributes,
                WindowsNativeFs.NativeFileOpen,
                WindowsNativeFs.NativeFileDirectoryFile,
                WindowsNativeFs.FileAttributeDirectory);
            try
            {
                WindowsNativeFs.ValidateDirectory(handle, DestinationPath, volumeSerial);
                MarkDelete(handle, DestinationPath);
            }
            finally { handle.Dispose(); }
        }

        public void RemoveEmptyDirectoryChecked(string expectedVolumeId, string expectedFileId)
        {
            uint expectedVolume = Convert.ToUInt32(expectedVolumeId, 16);
            ulong expectedFile = Convert.ToUInt64(expectedFileId, 16);
            AssertActive();
            SafeFileHandle handle = WindowsNativeFs.OpenRelative(
                parentHandle,
                LeafName,
                DestinationPath,
                WindowsNativeFs.Delete | WindowsNativeFs.FileReadAttributes,
                WindowsNativeFs.NativeFileOpen,
                WindowsNativeFs.NativeFileDirectoryFile,
                WindowsNativeFs.FileAttributeDirectory);
            try
            {
                WindowsNativeFs.ValidateDirectory(handle, DestinationPath, volumeSerial);
                WindowsNativeFs.ByHandleFileInformation information = WindowsNativeFs.GetInformation(handle, DestinationPath);
                ulong fileId = ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow;
                if (information.VolumeSerialNumber != expectedVolume || fileId != expectedFile)
                    throw new UnauthorizedAccessException("SAFEFS_IDENTITY_MISMATCH: Removal target identity changed: " + DestinationPath);
                MarkDelete(handle, DestinationPath);
            }
            finally { handle.Dispose(); }
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
        }
    }

    public static class WindowsHandleFs
    {
        private static string Normalize(string path)
        {
            if (String.IsNullOrWhiteSpace(path)) throw new ArgumentException("SAFEFS_EMPTY_PATH: A filesystem path is required.");
            string full = Path.GetFullPath(path);
            string root = Path.GetPathRoot(full);
            if (String.IsNullOrEmpty(root) || root.StartsWith("\\\\", StringComparison.Ordinal))
                throw new PlatformNotSupportedException("SAFEFS_HANDLE_MUTATION_UNAVAILABLE: UNC and non-drive paths are not supported by windows-handle-v1.");
            return full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }

        private static List<SafeFileHandle> OpenChain(string fullPath, out uint volumeSerial)
        {
            string volumeRoot = Path.GetPathRoot(fullPath);
            List<SafeFileHandle> handles = new List<SafeFileHandle>();
            SafeFileHandle volume = WindowsNativeFs.OpenVolumeRoot(volumeRoot, out volumeSerial);
            handles.Add(volume);
            string current = volumeRoot.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            try
            {
                string[] segments = WindowsNativeFs.SegmentsBelowVolume(fullPath, volumeRoot);
                for (int i = 0; i < segments.Length; i++)
                {
                    current = Path.Combine(current + Path.DirectorySeparatorChar, segments[i]);
                    SafeFileHandle next = WindowsNativeFs.OpenRelativeDirectory(handles[handles.Count - 1], segments[i], current, volumeSerial, WindowsNativeFs.NativeFileOpen);
                    handles.Add(next);
                }
                return handles;
            }
            catch
            {
                for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
                throw;
            }
        }

        public static WindowsDirectoryLease OpenParent(string authorizedRoot, string destination)
        {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                throw new PlatformNotSupportedException("SAFEFS_HANDLE_MUTATION_UNAVAILABLE: windows-handle-v1 requires Windows.");
            string root = Normalize(authorizedRoot);
            string target = Normalize(destination);
            WindowsNativeFs.AssertContained(root, target);
            string parent = Path.GetDirectoryName(target);
            if (String.IsNullOrEmpty(parent))
                throw new UnauthorizedAccessException("SAFEFS_OUTSIDE_ROOT: A destination parent is required.");
            uint volumeSerial;
            List<SafeFileHandle> handles = OpenChain(parent, out volumeSerial);
            return new WindowsDirectoryLease(handles, handles[handles.Count - 1], volumeSerial, root, target);
        }

        public static WindowsRootIdentity GetRootIdentity(string authorizedRoot)
        {
            string root = Normalize(authorizedRoot);
            uint volumeSerial;
            List<SafeFileHandle> handles = OpenChain(root, out volumeSerial);
            try
            {
                WindowsNativeFs.ByHandleFileInformation information = WindowsNativeFs.GetInformation(handles[handles.Count - 1], root);
                ulong fileId = ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow;
                return new WindowsRootIdentity(information.VolumeSerialNumber, fileId);
            }
            finally
            {
                for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
            }
        }

        public static void EnsureDirectory(string authorizedRoot, string destination)
        {
            string root = Normalize(authorizedRoot);
            string target = Normalize(destination);
            WindowsNativeFs.AssertContained(root, target);

            uint volumeSerial;
            List<SafeFileHandle> handles = OpenChain(root, out volumeSerial);
            string current = root;
            try
            {
                string relative = target.Substring(root.Length).Trim(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                string[] segments = relative.Length == 0
                    ? new string[0]
                    : relative.Split(new char[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar }, StringSplitOptions.RemoveEmptyEntries);
                for (int i = 0; i < segments.Length; i++)
                {
                    current = Path.Combine(current, segments[i]);
                    SafeFileHandle next = WindowsNativeFs.OpenRelativeDirectory(handles[handles.Count - 1], segments[i], current, volumeSerial, WindowsNativeFs.NativeFileOpenIf);
                    handles.Add(next);
                }
            }
            finally
            {
                for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
            }
        }
    }
}
