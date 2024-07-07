#ifndef _MKCUSTOM_H_
#define _MKCUSTOM_H_

#if defined(_WIN32)
  // for some reason this declaration is disabled when _POSIX_ is defined?
  char *__cdecl _fullpath(char *_FullPath, const char *_Path, size_t _SizeInBytes);
  // not sure where this function is supposed to be declared
  char *stpcpy(char *, const char *);
#endif

#if !defined(_GNU_SOURCE) && !defined(_WIN32)
#include <stddef.h> /* for size_t */
#include <string.h> /* for memcpy */
static inline void *mempcpy(void *dest, const void *src, size_t n) {
    memcpy(dest, src, n);
    return (char*)dest + n;
}
#else

#include <stddef.h> /* ptrdiff_t for function.c */

#endif

#endif // _MKCUSTOM_H_
