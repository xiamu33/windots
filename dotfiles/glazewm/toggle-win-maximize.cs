using System;
using System.Runtime.InteropServices;

// Portable Win32 helper: no paths, no GlazeWM/YASB config. Requires Windows + .NET Framework at build time only.
internal static class Program
{
    private const int SwRestore = 9;
    private const int SwMaximize = 3;
    private const int SwShowMaximized = 3;

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsZoomed(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowPlacement(IntPtr hWnd, ref WindowPlacement lpwndpl);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    private static bool IsMaximized(IntPtr hwnd)
    {
        if (IsZoomed(hwnd))
        {
            return true;
        }

        var placement = new WindowPlacement();
        placement.Length = Marshal.SizeOf(typeof(WindowPlacement));
        if (!GetWindowPlacement(hwnd, ref placement))
        {
            return false;
        }

        return placement.ShowCmd == SwShowMaximized;
    }

    private static void Main()
    {
        IntPtr hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero)
        {
            return;
        }

        int command = IsMaximized(hwnd) ? SwRestore : SwMaximize;
        ShowWindow(hwnd, command);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WindowPlacement
    {
        public int Length;
        public int Flags;
        public int ShowCmd;
        public Point MinPosition;
        public Point MaxPosition;
        public Rect NormalPosition;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
