#ifndef _MACH_VM_TYPES_H_
#define _MACH_VM_TYPES_H_

/*
 * Minimal <mach/vm_types.h> for the iOS armv7 cross build.
 *
 * The mach_vm_* family is the 64-bit VM address ABI that exists on 32-bit
 * armv7 iOS alongside the 32-bit vm_address_t (it is what the kernel's own
 * MIG interfaces use).  Widths are fixed by that ABI: address/size/offset
 * are all 64-bit, the protection and inheritance types are 32/32-bit.
 *
 * Verified on device (iPad 4, iOS 10.3.3, 2026-11-07): mach_vm_map() with
 * VM_FLAGS_ANYWHERE returned KERN_SUCCESS and an address, and the mapped
 * page was writable (wrote 42, read back 42).
 */

#include <stdint.h>
#include <mach/machine.h>

typedef uint64_t	mach_vm_address_t;
typedef uint64_t	mach_vm_size_t;
typedef uint64_t	mach_vm_offset_t;
typedef uint64_t	memory_object_offset_t;
typedef mach_port_t	mem_entry_name_port_t;

typedef int		vm_inherit_t;
typedef uint32_t	vm_prot_t;

#define VM_PROT_NONE	0x00
#define VM_PROT_READ	0x01
#define VM_PROT_WRITE	0x02
#define VM_PROT_EXECUTE	0x04
#define VM_PROT_DEFAULT	(VM_PROT_READ | VM_PROT_WRITE)
#define VM_PROT_ALL	(VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)

#define VM_INHERIT_SHARE	0
#define VM_INHERIT_COPY		1
#define VM_INHERIT_NONE		2

#endif
