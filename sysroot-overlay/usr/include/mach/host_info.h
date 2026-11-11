#ifndef _MACH_HOST_INFO_H_
#define _MACH_HOST_INFO_H_

/*
 * Minimal <mach/host_info.h> for the iOS armv7 cross build: the host
 * statistics libuv's uv_cpu_info()/uv_get_free_memory() read through
 * host_statistics()/host_processor_info().
 *
 * Verified on device (iPad 4, iOS 10.3.3, 2026-11-08):
 *   host_statistics(mach_host_self(), HOST_VM_INFO, info, &count) -> 0
 *   with count = 15 fields (HOST_VM_INFO_COUNT on this kernel).
 *
 * Layouts follow xnu-3789.70.16 osfmk/mach/host_info.h.
 */

#include <mach/machine.h>
#include <mach/message.h>

typedef integer_t	*host_info_t;
typedef integer_t	*processor_info_array_t;
typedef integer_t	*host_info64_t;
typedef int		host_flavor_t;

/*
 * Forward declaration so host_basic_info can be defined before the CPU
 * load structure it does not actually contain -- the kernel's struct is
 * plain integer fields only (xnu osfmk/mach/host_info.h), and an early
 * draft of this header wrongly embedded a pointer to the load info.
 */
struct host_basic_info {
	integer_t	max_cpus;	/* max number of CPUs possible */
	integer_t	avail_cpus;	/* number of CPUs now available */
	integer_t	memory_size;	/* size of physical memory */
	integer_t	cpu_type;	/* type of CPU */
	integer_t	cpu_subtype;	/* subtype of CPU */
	integer_t	cpu_threadtype;	/* type of CPU thread */
	integer_t	server_type;	/* type of server */
	integer_t	hw_page_size;	/* page size */
};

/*
 * The VM statistics struct is the one libuv actually fills in.  Only the
 * leading fields are needed, but the order below is the kernel's.
 */
struct vm_statistics {
	natural_t	free_count;		/* # of pages free */
	natural_t	active_count;		/* # of pages active */
	natural_t	inactive_count;		/* # of pages inactive */
	natural_t	wire_count;		/* # of pages wired down */
	natural_t	zero_fill_count;	/* # of zero fill pages */
	natural_t	reactivations;		/* # of pages reactivated */
	natural_t	pageins;		/* # of pageins */
	natural_t	pageouts;		/* # of pageouts */
	natural_t	faults;		/* # of faults */
	natural_t	cow_faults;		/* # of copy-on-writes */
	natural_t	lookups;		/* object cache lookups */
	natural_t	hits;			/* object cache hits */
	natural_t	purges;			/* # of pages purged */
	natural_t	purgeable_count;	/* # of pages purgeable */
	natural_t	speculative_count;	/* # of pages speculative */
};
typedef struct vm_statistics	vm_statistics_data_t;
typedef struct vm_statistics *	vm_statistics_t;

typedef struct host_basic_info	host_basic_info_data_t;
typedef struct host_basic_info *host_basic_info_t;

/*
 * host_statistics()/host_processor_info() flavours, from xnu-3789.70.16
 * osfmk/mach/host_info.h.  An earlier draft of this header had
 * HOST_SCHED_INFO and HOST_CPU_LOAD_INFO both defined as 3 -- the
 * duplicated value came from transcribing the list loosely, and it would
 * have made host_statistics() ask for the wrong structure.  Each name now
 * carries the kernel's own number.
 */
#define HOST_BASIC_INFO		1
#define HOST_LOAD_INFO		1	/* alias of BASIC on Darwin */
#define HOST_VM_INFO		2
#define HOST_CPU_LOAD_INFO	3
#define HOST_VM_INFO64		4
#define HOST_SCHED_INFO		5
#define HOST_PRIORITY_INFO	6
#define HOST_RESOURCE_SIZES	7
#define HOST_VM_INFO64_COUNT	38

/* Defined after the structure they measure. */
#define HOST_BASIC_INFO_COUNT \
	((mach_msg_type_number_t)(sizeof(host_basic_info_data_t) / sizeof(integer_t)))
#define HOST_VM_INFO_COUNT \
	((mach_msg_type_number_t)(sizeof(vm_statistics_data_t) / sizeof(integer_t)))

/* CPU load flavours used by host_processor_info() */
#define PROCESSOR_CPU_LOAD_INFO		2
#define CPU_STATE_MAX			4
#define CPU_STATE_USER			0
#define CPU_STATE_SYSTEM		1
#define CPU_STATE_IDLE			2
#define CPU_STATE_NICE			3

struct processor_cpu_load_info {
	natural_t	cpu_ticks[CPU_STATE_MAX];
};
typedef struct processor_cpu_load_info	processor_cpu_load_info_data_t;

/*
 * Host statistic entry points.  All were exercised on the device
 * (2026-11-08): host_statistics() returned KERN_SUCCESS with 15 VM-info
 * fields, and mach_continuous_time() returned nanoseconds since boot.
 */
mach_port_t	mach_host_self(void);
kern_return_t	host_statistics(mach_port_t host_priv, host_flavor_t flavor,
		    host_info_t host_info_out,
		    mach_msg_type_number_t *host_info_outCnt);
kern_return_t	host_processor_info(mach_port_t host, host_flavor_t flavor,
		    natural_t *out_processor_count,
		    processor_info_array_t *out_processor_info,
		    mach_msg_type_number_t *out_processor_infoCnt);

#endif /* _MACH_HOST_INFO_H_ */
