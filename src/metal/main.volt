// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in LICENSE.txt (BOOST ver. 1.0).
module metal.main;

import e820 = metal.e820;
import bochs = metal.drivers.bochs;
import mb1 = metal.boot.multiboot1;
import mb2 = metal.boot.multiboot2;
import gfx = metal.gfx;
import pci = metal.pci;
import acpi = metal.acpi;
import metal.drivers.serial;
import metal.printer;
import metal.stdc;


extern(C) void metal_main(uint magic, void* multibootInfo)
{
	writeln("Volt Metal");

	writeln("serial: Setting up 0x03F8");
	com1.setup(0x03F8);
	ring.addSink(com1.sink);

	parseMultiboot(magic, multibootInfo);

	pci.checkAllBuses();

	if (bochs.dev.loaded) {
		gfx.info.ptr = bochs.dev.ptr;
		gfx.info.w = bochs.dev.w;
		gfx.info.h = bochs.dev.h;
		gfx.info.pitch = bochs.dev.pitch;
		gfx.info.pixelOffX = 8;
		gfx.info.pixelOffY = 8;
		gfx.info.installSink();
	}

	e820.dumpMap();
	pci.dumpDevices();
}

void dumpMultiboot(uint magic, void* ptr)
{
	if (magic != mb2.Magic) {
		return;
	}

	auto info = cast(mb2.Info*) ptr;
	auto tag = cast(mb2.Tag*)&info[1];
	while (tag.type != mb2.TagType.END) {
		write("mb: ");
		writeHex(cast(ubyte)tag.type); write(" ");
		writeHex(tag.size); write(" ");
		size_t i = tag.type;
		if (i >= mb2.tagNames.length) {
			i = mb2.tagNames.length - 1;
		}
		writeln(mb2.tagNames[i]);

		// Get new address and align.
		auto addr = cast(size_t)tag + tag.size;
		if (addr % 8) {
			addr += 8 - addr % 8;
		}
		tag = cast(mb2.Tag*)addr;
	}
}

void dumpACPI(acpi.RSDPDescriptor* dec)
{
	auto rsdt = cast(acpi.RSDT*) dec.rsdtAddress;
	write("acpi: "); write(rsdt.h.signature); write(" ");
	writeHex(rsdt.h.length); write(" ");
	writeHex(cast(size_t)rsdt); writeln("");

	foreach (a; rsdt.array) {
		auto h = cast(acpi.Header*) a;
		write("acpi: "); write(h.signature); write(" ");
		writeHex(h.length); write(" ");
		writeHex(cast(size_t)h); writeln("");
	}
}

/**
 * Setup various devices and memory from multiboot information.
 */
void parseMultiboot(uint magic, void* ptr)
{
	write("mb: ");
	writeHex(magic);
	write(" ");
	writeHex(cast(size_t)ptr);
	writeln("");

	dumpMultiboot(magic, ptr);

	if (magic == mb1.Magic) {
		return parseMultiboot1(cast(mb1.Info*)ptr);
	} else if (magic == mb2.Magic) {
		return parseMultiboot2(cast(mb2.Info*)ptr);
	}
}

void parseMultiboot1(mb1.Info* info)
{
	if (info.flags & mb1.Info.Flags.Mmap) {
		e820.fromMultiboot1(info);
	}
}

void parseMultiboot2(mb2.Info* info)
{
	mb2.TagMmap* mmap;
	mb2.TagFramebuffer* fb;
	mb2.TagOldACPI* oldACPI;
	mb2.TagNewACPI* newACPI;

	// Frist search the tags for the mmap tag.
	auto tag = cast(mb2.Tag*)&info[1];
	while (tag.type != mb2.TagType.END) {
		switch (tag.type) with (mb2.TagType) {
		case MMAP:
			mmap = cast(typeof(mmap))tag;
			break;
		case FRAMEBUFFER:
			fb = cast(typeof(fb))tag;
			break;
		case ACPI_OLD:
			oldACPI = cast(typeof(oldACPI))tag;
			break;
		case ACPI_NEW:
			newACPI = cast(typeof(newACPI))tag;
			break;
		default:
		}

		// Get new address and align.
		auto addr = cast(size_t)tag + tag.size;
		if (addr % 8) {
			addr += 8 - addr % 8;
		}
		tag = cast(mb2.Tag*)addr;
	}

	if (mmap !is null) {
		e820.fromMultiboot2(mmap);
	}

	if (oldACPI !is null && newACPI is null) {
		dumpACPI(oldACPI.rsdp);
	}

	if (newACPI !is null) {
		dumpACPI(&newACPI.rsdp.v1);
	}

	if (fb !is null) {
		gfx.info.ptr = cast(void*)fb.framebuffer_addr;
		gfx.info.pitch = fb.framebuffer_pitch;
		gfx.info.w = fb.framebuffer_width;
		gfx.info.h = fb.framebuffer_height;
		gfx.info.pixelOffX = 8;
		gfx.info.pixelOffY = 8;
		gfx.info.installSink();
	}
}
