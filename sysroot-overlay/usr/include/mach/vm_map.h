#ifndef _MACH_VM_MAP_H_
#define _MACH_VM_MAP_H_


#ifdef __cplusplus
extern "C" {
#endif

/*
 * Minimal mach/vm_map.h for the iOS armv7 cross build: vm_deallocate()
 * only (gtest calls it to free task_threads()'s array).  vm_address_t is
 * natural_t on this ABI (xnu osfmk/mach/vm_types.h).
 */

#include <mach/mach_init.h>
#include <mach/vm_types.h>

typedef natural_t		vm_address_t;
#ifndef VM_SIZE_T_DEFINED
#define VM_SIZE_T_DEFINED
typedef natural_t		vm_size_t;
#endif

kern_return_t	vm_deallocate(vm_map_t target_task, vm_address_t address,
		    vm_size_t size);

/*
 * 64-bit VM entry points used by V8's iOS memory allocator
 * (src/base/ios-headers.h).  Both are exported by libSystem; mach_vm_map
 * was exercised on the device (see mach/vm_types.h).
 */
kern_return_t	mach_vm_remap(vm_map_t target_task, mach_vm_address_t *target_address,
		    mach_vm_size_t size, mach_vm_offset_t mask, int flags,
		    vm_map_t src_task, mach_vm_address_t src_address, boolean_t copy,
		    vm_prot_t *cur_protection, vm_prot_t *max_protection,
		    vm_inherit_t inheritance);
kern_return_t	mach_make_memory_entry_64(vm_map_t target_task,
		    mach_vm_size_t *size, memory_object_offset_t offset,
		    vm_prot_t permission, mem_entry_name_port_t *object,
		    mem_entry_name_port_t parent_entry);
kern_return_t	mach_vm_map(vm_map_t target_task, mach_vm_address_t *address,
		    mach_vm_size_t size, mach_vm_offset_t mask, int flags,
		    mem_entry_name_port_t object, memory_object_offset_t offset,
		    boolean_t copy, vm_prot_t cur_protection,
		    vm_prot_t max_protection, vm_inherit_t inheritance);


#ifdef __cplusplus
}
#endif

#endif
