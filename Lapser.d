module Main;

import xf.Common;
import xf.omg.core.Misc;

import xf.platform.win32.windef;
import xf.platform.win32.winuser;
import xf.platform.win32.wingdi;
import xf.platform.win32.winbase;

interface FI {
	import freeimage.FreeImage;
	import freeimage.FreeImageLoader;
}

import xf.omg.core.LinearAlgebra;
import xf.utils.Memory;

import tango.util.log.Trace;
import tango.util.Convert;
import tango.time.WallClock : Clock = WallClock;
import tango.text.convert.Format;
import tango.core.Thread;

alias xf.omg.core.Misc.min min;
alias xf.omg.core.Misc.max max;

import xf.omg.color.RGB;
import xf.omg.color.Quantize;


class ScreenShooter {
	vec2i	resolution;
	HWND	hwnd;
	
	
	FI.FIBITMAP* screenshot() {
		getResolution();
		return screenshot(vec2i.zero, resolution);
	}
	

	FI.FIBITMAP* screenshot(vec2i origin, vec2i size) {
		try {
			assert (origin.x + size.x <= resolution.x);
			assert (origin.y + size.y <= resolution.y);
			assert (size.x > 0);
			assert (size.y > 0);

			// the bitmap functions require that scanlines are aligned to DWORD boundaries
			size.x += (4 - size.x % 4) % 4;

			auto hdcScreen = GetDC(hwnd);
			if (hdcScreen is null) throw new Exception(`GetDC failed`);
			scope (exit) ReleaseDC(hwnd, hdcScreen);

			auto hdcCompatible = CreateCompatibleDC(hdcScreen);
			if (hdcCompatible is null) throw new Exception(`CreateCompatibleDC failed`);
			scope (exit) DeleteDC(hdcCompatible);

			// Create a compatible bitmap for hdcScreen.
			auto hbmScreen = CreateCompatibleBitmap(hdcScreen, size.x, size.y);
			if (!hbmScreen) throw new Exception(`hbmScreen failed`);
			scope (exit) DeleteObject(hbmScreen);

			// Select the bitmaps into the compatible DC. 
			if (!SelectObject(hdcCompatible, hbmScreen)) {
				throw new Exception(`Compatible Bitmap selection failed`); 
			}

			//Copy color data for the entire display into a bitmap that is selected into a compatible DC. 
			if (!BitBlt(hdcCompatible, 0, 0, size.x, size.y, hdcScreen, origin.x, origin.y, SRCCOPY | 0x40000000/*CAPTUREBLT*/)) {
				throw new Exception(`BitBlt failed`);
			}
			
			BITMAPINFO binfo;
			with (binfo.bmiHeader) {
				biSize = BITMAPINFOHEADER.sizeof;
				biWidth = size.x;
				biHeight = size.y;
				biPlanes = 1;
				biBitCount = 24;
				biCompression = BI_RGB;
			}
			
			if (0 == GetDIBits(hdcCompatible, hbmScreen, 0, size.y, null, &binfo, DIB_RGB_COLORS)) {
				throw new Exception(`GetDIBits failed(1)`);
			}

			auto image = FI.FreeImage_Allocate(size.x, size.y, 24);
			void* imageData = FI.FreeImage_GetBits(image);
			
			//Trace.formatln(`Copying {} scanlines`, size.y);
			if (size.y == GetDIBits(
					hdcCompatible,
					hbmScreen,
					0,
					size.y,
					imageData,
					&binfo,
					DIB_RGB_COLORS
			)) {
				// convert bgr to rgb
				uint max = size.x * size.y * 3;
				/+ubyte *ptr = cast(ubyte*)imageData;
				for (uint i = 0; i < max; i += 3) {
					ubyte t = ptr[i];
					ptr[i] = ptr[i+2];
					ptr[i+2] = t;
				}+/
				return image;
			} else {
				FI.FreeImage_Unload(image);
				throw new Exception(`GetDIBits failed(2)`);
			}
		} catch (Exception e) {
			Trace.formatln(`Exception in screenshot(): {} in {} : {}`, e.toString, e.file, e.line);
		}
		
		return null;
	}


	void getResolution() {
		resolution.x = GetSystemMetrics(SM_CXSCREEN);
		resolution.y = GetSystemMetrics(SM_CYSCREEN);
	}
}


void convertImg(alias from, alias to)(FI.FIBITMAP* image) {
	void* imageData = FI.FreeImage_GetBits(image);
	uword h = FI.FreeImage_GetHeight(image);
	uword w = FI.FreeImage_GetWidth(image);

	for (uword y = 0; y < h; ++y) {
		vec3[] data = (cast(vec3*)FI.FreeImage_GetScanLine(image, y))[0..w];
		foreach (ref d; data) {
			convertRGB!(from, to)(d, &d);
		}
	}
}


FI.FIBITMAP* linearFloatBGRToQuantizedSRGB(FI.FIBITMAP* input) {
	uword h = FI.FreeImage_GetHeight(input);
	uword w = FI.FreeImage_GetWidth(input);

	auto output = FI.FreeImage_Allocate(w, h, 24);
	if (output) {
		for (uword y = 0; y < h; ++y) {
			vec3[] srcData = (cast(vec3*)FI.FreeImage_GetScanLine(input, y))[0..w];
			vec3ub[] dstData = (cast(vec3ub*)FI.FreeImage_GetScanLine(output, y))[0..w];
			
			foreach (i, s; srcData) {
				vec3 d;
				convertRGB!(RGBSpace.Linear_sRGB, RGBSpace.sRGB)(s, &d);
				dstData[i] = quantizeColor!(Gamma.sRGB)(vec3(d.b, d.g, d.r));
			}
		}
	}
	return output;
}


void main(char[][] args) {
	int		hres;
	int		wres;
	float	qual;
	uint	delayMs;

	if (args.length != 5) {
		MessageBox(null, `Usage: lapser.exe x-res y-res quality[0-1] delay[ms]`, "unchi!", 0);
		return;
	}

	hres = to!(int)(args[1]);
	wres = to!(int)(args[2]);
	qual = to!(float)(args[3]);
	delayMs = to!(uint)(args[4]);

	if (FI.FreeImage_Initialise is null) {
		FI.FreeImage.load();
		FI.FreeImage_Initialise();
	}
	
	auto shooter = new ScreenShooter;
	
	Thread.getThis.priority(Thread.PRIORITY_MIN);

	void delayFunc() {
		Sleep(delayMs);

	idleSleep:
		LASTINPUTINFO inputInfo;
		inputInfo.cbSize = inputInfo.sizeof;
		GetLastInputInfo(&inputInfo);
		auto msIdle = GetTickCount() - inputInfo.dwTime;

		// So idle looks a bit like idle and the whole thing isn't too messy
		const idleMult = 3;

		if (msIdle > delayMs * idleMult) {
			const minIdleSleep = 100;
			uint ms = delayMs / 2;
			if (ms < minIdleSleep) {
				ms = minIdleSleep;
			}
			Sleep(ms);
			goto idleSleep;
		}
	}
	
	for (; true; delayFunc()) {
		FI.FIBITMAP* ss = null;
		
		try {
			ss = shooter.screenshot;
		} catch {}

		if (ss is null) {
			continue;
		}
			
		auto now = Clock.toDate();
		auto d = now.date;
		auto t = now.time;
		char[] fname = Format("{}-{:d2}-{:d2}-{:d2}_{:d2}_{:d2}.jpg", d.year, d.month, d.day, t.hours, t.minutes, t.seconds);
		//char[] fname = Format("{}-{:d2}-{:d2}-{:d2}_{:d2}_{:d2}.jp2", d.year, d.month, d.day, t.hours, t.minutes, t.seconds);
		//saver.save(image, fname, vec2i(560, 420), .85);

		final ss2 = FI.FreeImage_ConvertToRGBF(ss);
		FI.FreeImage_Unload(ss);
		
		if (!ss2) {
			continue;
		}

		convertImg!(RGBSpace.sRGB, RGBSpace.Linear_sRGB)(ss2);

		final scaled = FI.FreeImage_Rescale(
				ss2,
				hres,
				wres,
				FI.FILTER_CATMULLROM
		);
		FI.FreeImage_Unload(ss2);
		
		if (!scaled) {
			continue;
		}

		final toSave = linearFloatBGRToQuantizedSRGB(scaled);
		FI.FreeImage_Unload(scaled);

		if (!toSave) {
			continue;
		}

		FI.FreeImage_Save(
			FI.FIF_JPEG,
			//FI.FIF_J2K,
			toSave,
			toStringz(fname),
			max(0, min(100, rndint(qual * 100))) | 0x10000
			//rndint(max(1.0, min(512.0, pow(512.0, 1.0 - qual))))
		);
		FI.FreeImage_Unload(toSave);
	}
}
