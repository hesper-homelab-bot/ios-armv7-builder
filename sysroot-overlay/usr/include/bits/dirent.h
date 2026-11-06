/* Darwin (XNU) struct dirent.
 *
 * MEASURED, not guessed.  The toolchain here is musl's headers plus this
 * overlay, while the runtime libc is the device's libSystem -- so a wrong
 * struct here compiles and links cleanly and only misbehaves at run time.
 * This layout was read off an iPad 4 / iOS 10.3.3 / armv7 (xnu-3789) by
 * dumping the raw records returned by both getdirentries(2) and readdir(3)
 * (they are byte-identical, so readdir() is a pass-through) and cross-checking
 * every field against a directory of files with known name lengths:
 *
 *   offset  size  field           how it was confirmed
 *   ------  ----  --------------  ----------------------------------------
 *        0     8  d_ino           equals the CNID the raw record carries
 *        8     8  d_seekoff       telldir() returns its low 32 bits (1,2,3,...)
 *       16     2  d_reclen        record stride: readdir()'s pointer advances
 *                                 by exactly this much between entries
 *       18     2  d_namlen        equals strlen(d_name) for all 17 entries
 *       20     1  d_type          DT_DIR(4) for "." and "..", DT_REG(8) for
 *                                 every regular file
 *       21   n+1  d_name          the name starts here for every entry,
 *                                 including a 255-byte one
 *
 * musl's version of this header instead declares
 *     struct dirent { ino_t d_ino; off_t d_off; unsigned short d_reclen;
 *                    unsigned char d_type; char d_name[256]; };
 * which -- with this sysroot's 64-bit ino_t and off_t -- puts d_name at offset
 * 19.  Two bytes short.  Whatever sits at offset 19 is zero, so every entry
 * read through that offset comes back as the empty string: that is exactly the
 * OpenSSH sftp-server symptom "Server sent suspect path \"\" during readdir",
 * while get/put (which never call readdir) keep working.  Nothing in Darwin's
 * dirent has d_off at all, and it is the field that has to go.
 */
#ifndef _BITS_DIRENT_H
#define _BITS_DIRENT_H

/* Field-presence flags, kept for the consumers musl's <dirent.h> already had. */
#define _DIRENT_HAVE_D_RECLEN
#define _DIRENT_HAVE_D_TYPE
#define _DIRENT_HAVE_D_NAMLEN
#define _DIRENT_HAVE_D_SEEKOFF

/* Darwin spells this __DARWIN_MAXNAMLEN; 255 is the HFS/HFSX limit and the
 * device refuses a name longer than that in practice (see NAME_MAX below). */
#ifndef __DARWIN_MAXNAMLEN
#define __DARWIN_MAXNAMLEN 255
#endif

#include <bits/alltypes.h>

struct dirent {
	ino_t d_ino;             /* file number of entry */
	off_t d_seekoff;         /* seek offset / directory cookie */
	unsigned short d_reclen; /* length of this record */
	unsigned short d_namlen; /* length of the string in d_name */
	unsigned char d_type;    /* file type, see DT_* in <dirent.h> */
	char d_name[__DARWIN_MAXNAMLEN + 1];
};

#endif /* _BITS_DIRENT_H */
