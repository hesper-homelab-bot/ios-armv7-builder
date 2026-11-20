/*
 * <net/if_bond_internal.h> for the iOS armv7 cross build.
 *
 * source:   /home/hesper/scratch/sysctl-work/xnu [xnu-3789.70.16] bsd/net/if_bond_internal.h (via git cat-file)
 * repo:     https://github.com/apple-oss-distributions/xnu
 * tag/ref:  xnu-3789.70.16
 * fetched:  2026-11-20T01:58:37Z by tools/fetch-darwin-header.sh
 *
 * why:      <why the sysroot needs this header; which program includes it>
 *
 * [verified] <how this was proven on the device, or "unverified">
 *            e.g. probe prints MCAST_JOIN_GROUP=80, matches Darwin docs
 *
 * Numbers in this file are Darwin ABI.  Do not "fix" one to match a Linux
 * value seen in musl or glibc: the same name means something else there.
 */
/*
 * Copyright (c) 2011 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. The rights granted to you under the License
 * may not be used to create, or enable the creation or redistribution of,
 * unlawful or unlicensed copies of an Apple operating system, or to
 * circumvent, violate, or enable the circumvention or violation of, any
 * terms of an Apple operating system software license agreement.
 * 
 * Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_OSREFERENCE_LICENSE_HEADER_END@
 */
#ifndef _NET_IF_BOND_INTERNAL_H_

#if defined(__cplusplus)
extern "C" {
#endif
#ifdef KERNEL_PRIVATE
int bond_family_init(void);
#endif /* KERNEL_PRIVATE */
#if defined(__cplusplus)
}
#endif

#endif /* _NET_IF_BOND_INTERNAL_H_ */

