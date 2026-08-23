using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Lizard.AgentLayer.Native
{
    internal sealed class UnixFdHandle : SafeHandleMinusOneIsInvalid
    {
        internal UnixFdHandle(int fd) : base(true) { SetHandle(new IntPtr(fd)); }
        internal int FileDescriptor { get { return handle.ToInt32(); } }
        protected override bool ReleaseHandle() { return UnixNativeFs.close(handle.ToInt32()) == 0; }
    }

    internal sealed class UnixObjectIdentity
    {
        internal long Device;
        internal ulong Inode;
        internal uint Links;
        internal uint Mode;
        internal long Size;
        internal long LastWriteUtcTicks;
        internal long MountId;
        internal string MountPoint;
    }

    public sealed class UnixFileMetadata
    {
        internal UnixFileMetadata(UnixObjectIdentity identity)
        {
            Length = identity.Size;
            LastWriteUtcTicks = identity.LastWriteUtcTicks;
            Device = identity.Device;
            Inode = identity.Inode;
            MountId = identity.MountId;
        }
        public long Length { get; private set; }
        public long LastWriteUtcTicks { get; private set; }
        public long Device { get; private set; }
        public ulong Inode { get; private set; }
        public long MountId { get; private set; }
    }

    public sealed class UnixRootIdentity
    {
        internal UnixRootIdentity(UnixObjectIdentity identity)
        {
            Device = identity.Device;
            Inode = identity.Inode;
            MountId = identity.MountId;
            MountPoint = identity.MountPoint;
        }
        public long Device { get; private set; }
        public ulong Inode { get; private set; }
        public long MountId { get; private set; }
        public string MountPoint { get; private set; }
    }

    internal static class UnixNativeFs
    {
        internal const uint TypeMask = 0xF000;
        internal const uint TypeDirectory = 0x4000;
        internal const uint TypeRegular = 0x8000;
        internal const int SeekSet = 0;
        internal const int AtEmptyPath = 0x1000;
        internal const int AtNoAutomount = 0x800;
        internal const uint StatxBasicStats = 0x7ff;
        internal const uint StatxMountId = 0x1000;
        private static readonly DateTime UnixEpoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);

        [DllImport("libc", SetLastError = true)] internal static extern int open(string path, int flags, int mode);
        [DllImport("libc", SetLastError = true)] internal static extern int openat(int directory, string path, int flags, int mode);
        [DllImport("libc", SetLastError = true)] internal static extern int mkdirat(int directory, string path, uint mode);
        [DllImport("libc", SetLastError = true)] internal static extern int linkat(int oldDirectory, string oldPath, int newDirectory, string newPath, int flags);
        [DllImport("libc", SetLastError = true)] internal static extern int renameat(int oldDirectory, string oldPath, int newDirectory, string newPath);
        [DllImport("libc", EntryPoint = "renameat2", SetLastError = true)] private static extern int renameat2_linux(int oldDirectory, string oldPath, int newDirectory, string newPath, uint flags);
        [DllImport("libc", EntryPoint = "renameatx_np", SetLastError = true)] private static extern int renameatx_mac(int oldDirectory, string oldPath, int newDirectory, string newPath, uint flags);
        [DllImport("libc", SetLastError = true)] internal static extern int unlinkat(int directory, string path, int flags);
        [DllImport("libc", SetLastError = true)] internal static extern int fsync(int fd);
        [DllImport("libc", SetLastError = true)] internal static extern int close(int fd);
        [DllImport("libc", SetLastError = true)] internal static extern long read(int fd, IntPtr buffer, ulong count);
        [DllImport("libc", SetLastError = true)] internal static extern long write(int fd, IntPtr buffer, ulong count);
        [DllImport("libc", SetLastError = true)] internal static extern long lseek(int fd, long offset, int whence);
        [DllImport("libc", SetLastError = true)] internal static extern int statx(int directory, string path, int flags, uint mask, IntPtr buffer);
        [DllImport("libc", EntryPoint = "fstat$INODE64", SetLastError = true)] private static extern int fstat_inode64(int fd, IntPtr buffer);
        [DllImport("libc", EntryPoint = "fstat", SetLastError = true)] private static extern int fstat_unversioned(int fd, IntPtr buffer);
        [DllImport("libc", EntryPoint = "fstatfs$INODE64", SetLastError = true)] private static extern int fstatfs_inode64(int fd, IntPtr buffer);
        [DllImport("libc", EntryPoint = "fstatfs", SetLastError = true)] private static extern int fstatfs_unversioned(int fd, IntPtr buffer);

        internal static bool IsMac { get { return RuntimeInformation.IsOSPlatform(OSPlatform.OSX); } }

        private static int MacFstat(int fd, IntPtr buffer)
        {
            try { return fstat_inode64(fd, buffer); }
            catch (EntryPointNotFoundException) { return fstat_unversioned(fd, buffer); }
        }

        private static int MacFstatFs(int fd, IntPtr buffer)
        {
            try { return fstatfs_inode64(fd, buffer); }
            catch (EntryPointNotFoundException) { return fstatfs_unversioned(fd, buffer); }
        }

        internal static int ReadOnly { get { return 0; } }
        internal static int WriteOnly { get { return 1; } }
        internal static int Create { get { return IsMac ? 0x200 : 0x40; } }
        internal static int Exclusive { get { return IsMac ? 0x800 : 0x80; } }
        internal static int Directory { get { return IsMac ? 0x00100000 : 0x10000; } }
        internal static int NoFollow { get { return IsMac ? 0x100 : 0x20000; } }
        internal static int CloseOnExec { get { return IsMac ? 0x01000000 : 0x80000; } }
        internal static int AtRemoveDirectory { get { return IsMac ? 0x80 : 0x200; } }

        internal static int RenameNoReplace(int oldDirectory, string oldPath, int newDirectory, string newPath)
        {
            return IsMac
                ? renameatx_mac(oldDirectory, oldPath, newDirectory, newPath, 0x00000004)
                : renameat2_linux(oldDirectory, oldPath, newDirectory, newPath, 0x00000001);
        }

        internal static Exception NativeFailure(string operation, string path)
        {
            int error = Marshal.GetLastWin32Error();
            if (error == 2) return new FileNotFoundException("SAFEFS_FILE_MISSING: File does not exist: " + path);
            if (error == 17) return new IOException("SAFEFS_DESTINATION_EXISTS: Destination already exists: " + path);
            if (error == 18) return new UnauthorizedAccessException("SAFEFS_MOUNT_BOUNDARY: Native operation crossed a mount boundary: " + path);
            if ((!IsMac && error == 40) || (IsMac && error == 62)) return new UnauthorizedAccessException("SAFEFS_REPARSE_POINT: Linked path component is not allowed: " + path);
            return new Win32Exception(error, "SAFEFS_NATIVE_CALL_FAILED: " + operation + " failed for " + path);
        }

        internal static void AssertSegment(string segment)
        {
            if (String.IsNullOrWhiteSpace(segment) || segment == "." || segment == ".." || segment.IndexOfAny(new char[] { '/', '\0' }) >= 0)
                throw new UnauthorizedAccessException("SAFEFS_INVALID_SEGMENT: Invalid relative path segment: " + segment);
        }

        internal static UnixFdHandle OpenAbsoluteRoot()
        {
            int fd = open("/", ReadOnly | Directory | NoFollow | CloseOnExec, 0);
            if (fd < 0) throw NativeFailure("open", "/");
            return new UnixFdHandle(fd);
        }

        internal static UnixFdHandle OpenRelative(UnixFdHandle parent, string leaf, string displayPath, int access, bool directory, bool createNew)
        {
            AssertSegment(leaf);
            int flags = access | NoFollow | CloseOnExec;
            if (directory) flags |= Directory;
            if (createNew) flags |= Create | Exclusive;
            int fd = openat(parent.FileDescriptor, leaf, flags, createNew ? 438 : 0);
            if (fd < 0) throw NativeFailure("openat", displayPath);
            return new UnixFdHandle(fd);
        }

        private static long TicksFromUnix(long seconds, long nanoseconds)
        {
            try { return UnixEpoch.AddSeconds(seconds).AddTicks(nanoseconds / 100).Ticks; }
            catch { throw new IOException("SAFEFS_NATIVE_IDENTITY_INVALID: Invalid native timestamp."); }
        }

        private static string ReadNullTerminatedUtf8(IntPtr buffer, int offset, int maximum)
        {
            int length = 0;
            while (length < maximum && Marshal.ReadByte(buffer, offset + length) != 0) length++;
            byte[] bytes = new byte[length];
            if (length > 0) Marshal.Copy(new IntPtr(buffer.ToInt64() + offset), bytes, 0, length);
            return System.Text.Encoding.UTF8.GetString(bytes);
        }

        internal static UnixObjectIdentity GetIdentity(UnixFdHandle handle, string path)
        {
            if (IsMac) return GetMacIdentity(handle, path);
            return GetLinuxIdentity(handle, path);
        }

        private static UnixObjectIdentity GetLinuxIdentity(UnixFdHandle handle, string path)
        {
            // Offsets are the fixed Linux UAPI struct statx layout from include/uapi/linux/stat.h.
            IntPtr buffer = Marshal.AllocHGlobal(256);
            try
            {
                for (int i = 0; i < 256; i++) Marshal.WriteByte(buffer, i, 0);
                if (statx(handle.FileDescriptor, "", AtEmptyPath | AtNoAutomount, StatxBasicStats | StatxMountId, buffer) != 0)
                    throw NativeFailure("statx", path);
                uint mask = (uint)Marshal.ReadInt32(buffer, 0);
                if ((mask & (StatxBasicStats | StatxMountId)) != (StatxBasicStats | StatxMountId))
                    throw new PlatformNotSupportedException("SAFEFS_CAPABILITY_UNAVAILABLE: statx did not return basic and mount identity.");
                UnixObjectIdentity identity = new UnixObjectIdentity();
                identity.Links = (uint)Marshal.ReadInt32(buffer, 16);
                identity.Mode = (uint)(ushort)Marshal.ReadInt16(buffer, 28);
                identity.Inode = (ulong)Marshal.ReadInt64(buffer, 32);
                identity.Size = Marshal.ReadInt64(buffer, 40);
                long seconds = Marshal.ReadInt64(buffer, 112);
                long nanoseconds = (uint)Marshal.ReadInt32(buffer, 120);
                identity.LastWriteUtcTicks = TicksFromUnix(seconds, nanoseconds);
                long deviceMajor = (uint)Marshal.ReadInt32(buffer, 136);
                long deviceMinor = (uint)Marshal.ReadInt32(buffer, 140);
                identity.Device = (deviceMajor << 32) | deviceMinor;
                identity.MountId = Marshal.ReadInt64(buffer, 144);
                identity.MountPoint = identity.MountId.ToString(System.Globalization.CultureInfo.InvariantCulture);
                return identity;
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        private static UnixObjectIdentity GetMacIdentity(UnixFdHandle handle, string path)
        {
            // Offsets are Darwin's 64-bit-inode struct stat and struct statfs64 layouts.
            IntPtr statBuffer = Marshal.AllocHGlobal(256);
            IntPtr fsBuffer = Marshal.AllocHGlobal(2304);
            try
            {
                if (MacFstat(handle.FileDescriptor, statBuffer) != 0) throw NativeFailure("fstat", path);
                if (MacFstatFs(handle.FileDescriptor, fsBuffer) != 0) throw NativeFailure("fstatfs", path);
                UnixObjectIdentity identity = new UnixObjectIdentity();
                identity.Device = (uint)Marshal.ReadInt32(statBuffer, 0);
                identity.Mode = (uint)(ushort)Marshal.ReadInt16(statBuffer, 4);
                identity.Links = (uint)(ushort)Marshal.ReadInt16(statBuffer, 6);
                identity.Inode = (ulong)Marshal.ReadInt64(statBuffer, 8);
                identity.Size = Marshal.ReadInt64(statBuffer, 96);
                identity.LastWriteUtcTicks = TicksFromUnix(Marshal.ReadInt64(statBuffer, 48), Marshal.ReadInt64(statBuffer, 56));
                long fsid0 = (uint)Marshal.ReadInt32(fsBuffer, 48);
                long fsid1 = (uint)Marshal.ReadInt32(fsBuffer, 52);
                identity.MountId = (fsid0 << 32) | fsid1;
                identity.MountPoint = ReadNullTerminatedUtf8(fsBuffer, 88, 1024);
                if (String.IsNullOrWhiteSpace(identity.MountPoint))
                    throw new PlatformNotSupportedException("SAFEFS_CAPABILITY_UNAVAILABLE: fstatfs returned no mount point.");
                return identity;
            }
            finally { Marshal.FreeHGlobal(statBuffer); Marshal.FreeHGlobal(fsBuffer); }
        }

        internal static void ValidateDirectory(UnixFdHandle handle, string path, UnixObjectIdentity root, bool enforceBoundary)
        {
            UnixObjectIdentity identity = GetIdentity(handle, path);
            if ((identity.Mode & TypeMask) != TypeDirectory) throw new UnauthorizedAccessException("SAFEFS_NOT_DIRECTORY: Expected a directory: " + path);
            if (enforceBoundary && (identity.Device != root.Device || identity.MountId != root.MountId))
                throw new UnauthorizedAccessException("SAFEFS_MOUNT_BOUNDARY: Directory crosses the authorized mount: " + path);
        }

        internal static UnixObjectIdentity ValidateFile(UnixFdHandle handle, string path, UnixObjectIdentity root)
        {
            UnixObjectIdentity identity = GetIdentity(handle, path);
            if ((identity.Mode & TypeMask) != TypeRegular) throw new UnauthorizedAccessException("SAFEFS_NOT_FILE: Expected an ordinary file: " + path);
            if (identity.Links > 1) throw new UnauthorizedAccessException("SAFEFS_REPARSE_POINT: Hard-linked terminal file is not allowed: " + path);
            if (identity.Device != root.Device || identity.MountId != root.MountId)
                throw new UnauthorizedAccessException("SAFEFS_MOUNT_BOUNDARY: File crosses the authorized mount: " + path);
            return identity;
        }

        internal static void WriteAll(UnixFdHandle handle, byte[] bytes, string path)
        {
            GCHandle pinned = GCHandle.Alloc(bytes, GCHandleType.Pinned);
            try
            {
                int offset = 0;
                while (offset < bytes.Length)
                {
                    IntPtr pointer = new IntPtr(pinned.AddrOfPinnedObject().ToInt64() + offset);
                    long written;
                    do { written = write(handle.FileDescriptor, pointer, (ulong)(bytes.Length - offset)); }
                    while (written < 0 && Marshal.GetLastWin32Error() == 4);
                    if (written <= 0) throw NativeFailure("write", path);
                    offset += checked((int)written);
                }
            }
            finally { pinned.Free(); }
        }

        internal static byte[] ReadAll(UnixFdHandle handle, string path, UnixObjectIdentity identity, long maximumBytes)
        {
            if (identity.Size < 0 || identity.Size > Int32.MaxValue || identity.Size > maximumBytes)
                throw new IOException("SAFEFS_FILE_TOO_LARGE: Protected file exceeds the supported in-memory size: " + path);
            byte[] bytes = new byte[(int)identity.Size];
            if (bytes.Length == 0) return bytes;
            GCHandle pinned = GCHandle.Alloc(bytes, GCHandleType.Pinned);
            try
            {
                int offset = 0;
                while (offset < bytes.Length)
                {
                    IntPtr pointer = new IntPtr(pinned.AddrOfPinnedObject().ToInt64() + offset);
                    long count;
                    do { count = read(handle.FileDescriptor, pointer, (ulong)(bytes.Length - offset)); }
                    while (count < 0 && Marshal.GetLastWin32Error() == 4);
                    if (count < 0) throw NativeFailure("read", path);
                    if (count == 0) break;
                    offset += checked((int)count);
                }
                if (offset != bytes.Length) throw new IOException("SAFEFS_CHANGED_DURING_READ: File length changed during protected read: " + path);
                return bytes;
            }
            finally { pinned.Free(); }
        }
    }

    public sealed class UnixDirectoryLease : IDisposable
    {
        private readonly List<UnixFdHandle> handles;
        private readonly UnixFdHandle parent;
        private readonly UnixObjectIdentity rootIdentity;
        private bool disposed;

        internal UnixDirectoryLease(List<UnixFdHandle> openHandles, UnixFdHandle parentHandle, UnixObjectIdentity root, string authorizedRoot, string destination)
        {
            handles = openHandles;
            parent = parentHandle;
            rootIdentity = root;
            AuthorizedRoot = authorizedRoot;
            DestinationPath = destination;
            LeafName = Path.GetFileName(destination);
        }

        public string AuthorizedRoot { get; private set; }
        public string DestinationPath { get; private set; }
        public string LeafName { get; private set; }

        private UnixFdHandle OpenExistingFile(int access)
        {
            UnixFdHandle handle = UnixNativeFs.OpenRelative(parent, LeafName, DestinationPath, access, false, false);
            try { UnixNativeFs.ValidateFile(handle, DestinationPath, rootIdentity); return handle; }
            catch { handle.Dispose(); throw; }
        }

        private UnixFdHandle OpenExistingDirectory()
        {
            UnixFdHandle handle = UnixNativeFs.OpenRelative(parent, LeafName, DestinationPath, UnixNativeFs.ReadOnly, true, false);
            try { UnixNativeFs.ValidateDirectory(handle, DestinationPath, rootIdentity, true); return handle; }
            catch { handle.Dispose(); throw; }
        }

        public byte[] ReadExisting(long maximumBytes)
        {
            using (UnixFdHandle handle = OpenExistingFile(UnixNativeFs.ReadOnly))
            {
                UnixObjectIdentity identity = UnixNativeFs.ValidateFile(handle, DestinationPath, rootIdentity);
                return UnixNativeFs.ReadAll(handle, DestinationPath, identity, maximumBytes);
            }
        }

        public UnixFileMetadata GetExistingMetadata()
        {
            using (UnixFdHandle handle = OpenExistingFile(UnixNativeFs.ReadOnly))
                return new UnixFileMetadata(UnixNativeFs.ValidateFile(handle, DestinationPath, rootIdentity));
        }

        public UnixFileMetadata GetExistingDirectoryMetadata()
        {
            using (UnixFdHandle handle = OpenExistingDirectory())
            {
                UnixNativeFs.ValidateDirectory(handle, DestinationPath, rootIdentity, true);
                return new UnixFileMetadata(UnixNativeFs.GetIdentity(handle, DestinationPath));
            }
        }

        private void AssertExistingDestinationSafe()
        {
            try { using (UnixFdHandle handle = OpenExistingFile(UnixNativeFs.ReadOnly)) { } }
            catch (FileNotFoundException) { }
        }

        public void WriteAtomic(byte[] bytes, bool replace)
        {
            if (disposed) throw new ObjectDisposedException("UnixDirectoryLease");
            if (replace) AssertExistingDestinationSafe();
            string stageName = ".lizard-stage-" + Guid.NewGuid().ToString("N") + ".tmp";
            UnixFdHandle stage = UnixNativeFs.OpenRelative(parent, stageName, stageName, UnixNativeFs.WriteOnly, false, true);
            bool renamed = false;
            try
            {
                UnixNativeFs.ValidateFile(stage, stageName, rootIdentity);
                UnixNativeFs.WriteAll(stage, bytes, stageName);
                if (UnixNativeFs.fsync(stage.FileDescriptor) != 0) throw UnixNativeFs.NativeFailure("fsync", stageName);
                if (replace)
                {
                    if (UnixNativeFs.renameat(parent.FileDescriptor, stageName, parent.FileDescriptor, LeafName) != 0)
                        throw UnixNativeFs.NativeFailure("renameat", DestinationPath);
                }
                else
                {
                    // linkat creates the destination name only if absent. Removing the stage name
                    // afterwards leaves the same inode installed without a check-then-rename race.
                    if (UnixNativeFs.linkat(parent.FileDescriptor, stageName, parent.FileDescriptor, LeafName, 0) != 0)
                        throw UnixNativeFs.NativeFailure("linkat", DestinationPath);
                    if (UnixNativeFs.unlinkat(parent.FileDescriptor, stageName, 0) != 0)
                        throw UnixNativeFs.NativeFailure("unlinkat(stage)", stageName);
                }
                renamed = true;
            }
            finally
            {
                stage.Dispose();
                if (!renamed) UnixNativeFs.unlinkat(parent.FileDescriptor, stageName, 0);
            }
        }

        public void RemoveFile()
        {
            using (UnixFdHandle handle = OpenExistingFile(UnixNativeFs.ReadOnly)) { }
            if (UnixNativeFs.unlinkat(parent.FileDescriptor, LeafName, 0) != 0) throw UnixNativeFs.NativeFailure("unlinkat", DestinationPath);
        }

        private static bool IdentityMatches(UnixObjectIdentity identity, string expectedDeviceId, string expectedFileId, string expectedMountId)
        {
            long expectedDevice = unchecked((long)Convert.ToUInt64(expectedDeviceId, 16));
            ulong expectedFile = Convert.ToUInt64(expectedFileId, 16);
            long expectedMount = Convert.ToInt64(expectedMountId, System.Globalization.CultureInfo.InvariantCulture);
            return identity.Device == expectedDevice && identity.Inode == expectedFile && identity.MountId == expectedMount;
        }

        private void RestoreQuarantine(string quarantineName, string displayPath)
        {
            if (UnixNativeFs.RenameNoReplace(parent.FileDescriptor, quarantineName, parent.FileDescriptor, LeafName) != 0)
                throw new IOException("SAFEFS_QUARANTINE_RECOVERY_REQUIRED: Removal identity changed and quarantine could not be restored without overwrite: " + displayPath + "; quarantine=" + quarantineName);
        }

        public void RemoveFileChecked(string expectedDeviceId, string expectedFileId, string expectedMountId)
        {
            string quarantine = ".lizard-delete-" + Guid.NewGuid().ToString("N") + ".tmp";
            if (UnixNativeFs.renameat(parent.FileDescriptor, LeafName, parent.FileDescriptor, quarantine) != 0)
                throw UnixNativeFs.NativeFailure("renameat(delete-quarantine)", DestinationPath);
            bool quarantinePresent = true;
            try
            {
                using (UnixFdHandle moved = UnixNativeFs.OpenRelative(parent, quarantine, quarantine, UnixNativeFs.ReadOnly, false, false))
                {
                    UnixObjectIdentity identity = UnixNativeFs.ValidateFile(moved, DestinationPath, rootIdentity);
                    if (!IdentityMatches(identity, expectedDeviceId, expectedFileId, expectedMountId))
                    {
                        RestoreQuarantine(quarantine, DestinationPath);
                        quarantinePresent = false;
                        throw new UnauthorizedAccessException("SAFEFS_IDENTITY_MISMATCH: Removal target identity changed: " + DestinationPath);
                    }
                }
                if (UnixNativeFs.unlinkat(parent.FileDescriptor, quarantine, 0) != 0) throw UnixNativeFs.NativeFailure("unlinkat(delete-quarantine)", DestinationPath);
                quarantinePresent = false;
            }
            catch
            {
                // If the validated object was not deleted, recover its original name without replacing a raced entry.
                if (quarantinePresent) { try { RestoreQuarantine(quarantine, DestinationPath); } catch (IOException) { throw; } catch { } }
                throw;
            }
        }

        public void RemoveEmptyDirectory()
        {
            using (UnixFdHandle handle = UnixNativeFs.OpenRelative(parent, LeafName, DestinationPath, UnixNativeFs.ReadOnly, true, false))
                UnixNativeFs.ValidateDirectory(handle, DestinationPath, rootIdentity, true);
            if (UnixNativeFs.unlinkat(parent.FileDescriptor, LeafName, UnixNativeFs.AtRemoveDirectory) != 0) throw UnixNativeFs.NativeFailure("unlinkat(directory)", DestinationPath);
        }

        public void RemoveEmptyDirectoryChecked(string expectedDeviceId, string expectedFileId, string expectedMountId)
        {
            string quarantine = ".lizard-delete-" + Guid.NewGuid().ToString("N") + ".tmp";
            if (UnixNativeFs.renameat(parent.FileDescriptor, LeafName, parent.FileDescriptor, quarantine) != 0)
                throw UnixNativeFs.NativeFailure("renameat(directory-quarantine)", DestinationPath);
            bool quarantinePresent = true;
            try
            {
                using (UnixFdHandle moved = UnixNativeFs.OpenRelative(parent, quarantine, quarantine, UnixNativeFs.ReadOnly, true, false))
                {
                    UnixNativeFs.ValidateDirectory(moved, DestinationPath, rootIdentity, true);
                    UnixObjectIdentity identity = UnixNativeFs.GetIdentity(moved, DestinationPath);
                    if (!IdentityMatches(identity, expectedDeviceId, expectedFileId, expectedMountId))
                    {
                        RestoreQuarantine(quarantine, DestinationPath);
                        quarantinePresent = false;
                        throw new UnauthorizedAccessException("SAFEFS_IDENTITY_MISMATCH: Removal target identity changed: " + DestinationPath);
                    }
                }
                if (UnixNativeFs.unlinkat(parent.FileDescriptor, quarantine, UnixNativeFs.AtRemoveDirectory) != 0) throw UnixNativeFs.NativeFailure("unlinkat(directory-quarantine)", DestinationPath);
                quarantinePresent = false;
            }
            catch
            {
                if (quarantinePresent) { try { RestoreQuarantine(quarantine, DestinationPath); } catch (IOException) { throw; } catch { } }
                throw;
            }
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
        }
    }

    public static class UnixHandleFs
    {
        private static string Normalize(string path)
        {
            string full = Path.GetFullPath(path);
            if (!full.StartsWith("/", StringComparison.Ordinal)) throw new UnauthorizedAccessException("SAFEFS_OUTSIDE_ROOT: Unix path must be absolute.");
            return full == "/" ? full : full.TrimEnd('/');
        }

        private static string[] Segments(string fullPath)
        {
            string relative = fullPath.Trim('/');
            return relative.Length == 0 ? new string[0] : relative.Split(new char[] { '/' }, StringSplitOptions.RemoveEmptyEntries);
        }

        private static List<UnixFdHandle> OpenRootChain(string root, out UnixObjectIdentity rootIdentity)
        {
            List<UnixFdHandle> handles = new List<UnixFdHandle>();
            UnixFdHandle current = UnixNativeFs.OpenAbsoluteRoot();
            handles.Add(current);
            string display = "/";
            try
            {
                string[] segments = Segments(root);
                for (int i = 0; i < segments.Length; i++)
                {
                    display = display == "/" ? "/" + segments[i] : display + "/" + segments[i];
                    current = UnixNativeFs.OpenRelative(current, segments[i], display, UnixNativeFs.ReadOnly, true, false);
                    UnixNativeFs.ValidateDirectory(current, display, null, false);
                    handles.Add(current);
                }
                rootIdentity = UnixNativeFs.GetIdentity(handles[handles.Count - 1], root);
                return handles;
            }
            catch
            {
                for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
                throw;
            }
        }

        private static void AssertContained(string root, string destination)
        {
            string prefix = root == "/" ? "/" : root + "/";
            if (destination == root || !destination.StartsWith(prefix, StringComparison.Ordinal))
                throw new UnauthorizedAccessException("SAFEFS_OUTSIDE_ROOT: Destination escapes or equals the authorized root: " + destination);
        }

        public static UnixDirectoryLease OpenParent(string authorizedRoot, string destination)
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) throw new PlatformNotSupportedException("SAFEFS_CAPABILITY_UNAVAILABLE: Unix backend requires Unix.");
            string root = Normalize(authorizedRoot);
            string target = Normalize(destination);
            AssertContained(root, target);
            string parentPath = Path.GetDirectoryName(target);
            UnixObjectIdentity rootIdentity;
            List<UnixFdHandle> handles = OpenRootChain(root, out rootIdentity);
            UnixFdHandle current = handles[handles.Count - 1];
            string relative = parentPath.Substring(root.Length).Trim('/');
            string display = root;
            try
            {
                foreach (string segment in (relative.Length == 0 ? new string[0] : relative.Split('/')))
                {
                    display = display == "/" ? "/" + segment : display + "/" + segment;
                    current = UnixNativeFs.OpenRelative(current, segment, display, UnixNativeFs.ReadOnly, true, false);
                    UnixNativeFs.ValidateDirectory(current, display, rootIdentity, true);
                    handles.Add(current);
                }
                return new UnixDirectoryLease(handles, current, rootIdentity, root, target);
            }
            catch
            {
                for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
                throw;
            }
        }

        public static void EnsureDirectory(string authorizedRoot, string destination)
        {
            string root = Normalize(authorizedRoot);
            string target = Normalize(destination);
            AssertContained(root, target);
            UnixObjectIdentity rootIdentity;
            List<UnixFdHandle> handles = OpenRootChain(root, out rootIdentity);
            UnixFdHandle current = handles[handles.Count - 1];
            string display = root;
            try
            {
                string relative = target.Substring(root.Length).Trim('/');
                foreach (string segment in (relative.Length == 0 ? new string[0] : relative.Split('/')))
                {
                    display = display == "/" ? "/" + segment : display + "/" + segment;
                    UnixFdHandle next = null;
                    try { next = UnixNativeFs.OpenRelative(current, segment, display, UnixNativeFs.ReadOnly, true, false); }
                    catch (FileNotFoundException)
                    {
                        if (UnixNativeFs.mkdirat(current.FileDescriptor, segment, 511) != 0 && Marshal.GetLastWin32Error() != 17)
                            throw UnixNativeFs.NativeFailure("mkdirat", display);
                        next = UnixNativeFs.OpenRelative(current, segment, display, UnixNativeFs.ReadOnly, true, false);
                    }
                    UnixNativeFs.ValidateDirectory(next, display, rootIdentity, true);
                    handles.Add(next);
                    current = next;
                }
            }
            finally { for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose(); }
        }

        public static UnixRootIdentity GetRootIdentity(string authorizedRoot)
        {
            string root = Normalize(authorizedRoot);
            UnixObjectIdentity identity;
            List<UnixFdHandle> handles = OpenRootChain(root, out identity);
            try { return new UnixRootIdentity(identity); }
            finally { for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose(); }
        }
    }
}
