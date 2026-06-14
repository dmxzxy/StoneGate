using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;
using System.Threading;

class Program {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    
    static void Main(string[] args) {
        IntPtr hwnd = (IntPtr)long.Parse(args[0]);
        SetForegroundWindow(hwnd);
        Thread.Sleep(500);
        RECT r;
        GetWindowRect(hwnd, out r);
        int w = r.Right - r.Left;
        int h = r.Bottom - r.Top;
        Console.WriteLine($"Window rect: {r.Left},{r.Top} {w}x{h}");
        if (w <= 0 || h <= 0) { Console.Error.WriteLine("Bad window size"); return; }
        using Bitmap bmp = new Bitmap(w, h);
        using Graphics g = Graphics.FromImage(bmp);
        g.CopyFromScreen(r.Left, r.Top, 0, 0, bmp.Size, CopyPixelOperation.SourceCopy);
        bmp.Save(args[1], ImageFormat.Png);
        Console.WriteLine("Saved to " + args[1]);
    }
}
