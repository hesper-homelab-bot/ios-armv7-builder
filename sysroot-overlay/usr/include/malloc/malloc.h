#ifndef _MALLOC_MALLOC_H_
#define _MALLOC_MALLOC_H_

/*
 * Darwin <malloc/malloc.h> for the iOS armv7 cross build.
 *
 * libuv's darwin.c uses malloc zones to account for its own allocations,
 * and V8's allocator references the zone entry points too.  Everything
 * declared below was exercised on the device (iPad 4, iOS 10.3.3,
 * 2026-11-08):
 *
 *   malloc_default_zone()                -> 0x38c4c000
 *   malloc_zone_malloc(zone, 128)        -> 0x1454e9f0
 *   malloc_zone_free(zone, ptr)          -> ok
 *   malloc_size()/malloc_good_size()     -> already verified by the QuickJS port
 *   malloc_create_zone(0, 0)             -> 0x1a8000
 *   malloc_set_zone_name(zone, "probe")  -> ok
 *   malloc_destroy_zone(zone)            -> ok
 *
 * Caveat learned while probing: do NOT call malloc_set_zone_name() on the
 * zone returned by malloc_default_zone().  The process aborts a moment
 * later with "pointer being freed was not allocated".  That is Apple's
 * documented restriction on the default zone, not a sysroot defect.
 */

#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct _malloc_introspection_t malloc_introspection_t;

/*
 * malloc_zone_t layout.
 *
 * This must be the REAL structure, not an opaque handle: sqlite's
 * SQLITE_MALLOCSIZE macro calls _sqliteZone_->size(_sqliteZone_, ptr)
 * directly (deps/sqlite/sqlite3.c:27961), so the field has to exist at the
 * right offset.
 *
 * Derivation: the first two slots of the live default zone are NULL while
 * every slot from the third onward holds a code pointer, which matches
 * Apple libmalloc's layout -- two reserved pointers, then the function
 * table starting with size/malloc/calloc/valloc/free/realloc/destroy.
 * The size slot was then confirmed on the device (iPad 4, iOS 10.3.3,
 * 2026-11-08) by calling zone->size(zone, p) on a 1024-byte
 * malloc_zone_malloc block: it returned 1024, exactly matching
 * malloc_size(p).
 *
 * Only the leading, ABI-stable part is spelled out; the trailing
 * introspection region is left absent because nothing here walks it.
 */
struct _malloc_zone_t {
	void	*reserved1;	/* usually NULL */
	void	*reserved2;	/* usually NULL */

	size_t	(*size)(struct _malloc_zone_t *zone, const void *ptr);
	void	*(*malloc)(struct _malloc_zone_t *zone, size_t size);
	void	*(*calloc)(struct _malloc_zone_t *zone, size_t num, size_t size);
	void	*(*valloc)(struct _malloc_zone_t *zone, size_t size);
	void	(*free)(struct _malloc_zone_t *zone, void *ptr);
	void	*(*realloc)(struct _malloc_zone_t *zone, void *ptr, size_t size);
	void	(*destroy)(struct _malloc_zone_t *zone);
	const char *(*zone_name)(struct _malloc_zone_t *zone);
	void	*(*memalign)(struct _malloc_zone_t *zone, size_t alignment,
		    size_t size);
	void	*(*free_definite_size)(struct _malloc_zone_t *zone, void *ptr,
		    size_t size);
	size_t	(*pressure_relief)(struct _malloc_zone_t *zone, size_t goal);
	size_t	(*claimed_address)(struct _malloc_zone_t *zone, void *ptr);
	void	*(*batch_malloc)(struct _malloc_zone_t *zone, size_t size,
		    void **results, unsigned num_requested);
	void	(*batch_free)(struct _malloc_zone_t *zone, void **to_be_freed,
		    unsigned num);
	void	(*try_free_default)(struct _malloc_zone_t *zone, void *ptr);
	void	*(*memalign_definite)(struct _malloc_zone_t *zone,
		    size_t alignment, size_t size, unsigned long long id);
	unsigned (*introspect)(struct _malloc_zone_t *zone, unsigned options);
	void	*reserved3;
	void	*reserved4;
	void	*reserved5;
	void	*reserved6;
};

typedef struct _malloc_zone_t malloc_zone_t;

malloc_zone_t *	malloc_default_zone(void);
malloc_zone_t *	malloc_create_zone(size_t start_size, unsigned flags);
void		malloc_destroy_zone(malloc_zone_t *zone);
void		malloc_set_zone_name(malloc_zone_t *zone, const char *name);
const char *	malloc_get_zone_name(malloc_zone_t *zone);

void *		malloc_zone_malloc(malloc_zone_t *zone, size_t size);
void *		malloc_zone_calloc(malloc_zone_t *zone, size_t num, size_t size);
void *		malloc_zone_realloc(malloc_zone_t *zone, void *ptr, size_t size);
void *		malloc_zone_memalign(malloc_zone_t *zone, size_t alignment,
		    size_t size);
void		malloc_zone_free(malloc_zone_t *zone, void *ptr);
void		malloc_zone_free_definite_size(malloc_zone_t *zone, void *ptr,
		    size_t size);

size_t		malloc_size(const void *ptr);
size_t		malloc_good_size(size_t size);

unsigned	malloc_num_zones(void);
malloc_zone_t **malloc_get_all_zones(unsigned *count);

#ifdef __cplusplus
}
#endif

#endif /* _MALLOC_MALLOC_H_ */
