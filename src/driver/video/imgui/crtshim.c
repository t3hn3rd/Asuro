/*
 * crtshim.c  -  Bare-metal C runtime library shim for ImGui
 *
 * Provides every libc symbol that Dear ImGui / cimgui references, without
 * pulling in newlib or any other hosted runtime.  All heap operations are
 * forwarded to the Pascal kernel allocator via two exported Pascal symbols
 * (imgui_c_alloc / imgui_c_free) that are defined in imgui.pas.
 */

/* --------------------------------------------------------------------------
 * Compiler hints
 * -------------------------------------------------------------------------- */
typedef unsigned int   size_t;
typedef int            ptrdiff_t;
typedef long long      intmax_t;
typedef unsigned long long uintmax_t;
typedef unsigned int   uintptr_t;
typedef int            ssize_t;

/* Needed by some ImGui template helpers */
#define NULL ((void*)0)

/* --------------------------------------------------------------------------
 * Pascal allocator bridge (symbols defined in imgui.pas with cdecl+public)
 * -------------------------------------------------------------------------- */
extern void* imgui_c_alloc(unsigned int size);
extern void  imgui_c_free(void* ptr);
/* FPC uses register calling convention: first param in EAX.
   regparm(3) tells GCC to pass first 3 params in EAX,EDX,ECX. */
extern void  console_writestring(const char* str) __attribute__((regparm(3)));

/* Global allocation counter — readable from Pascal/C for diagnostics */
unsigned int crt_malloc_count = 0;
unsigned int crt_malloc_last_size = 0;

/* --------------------------------------------------------------------------
 * Internal allocation header (lets realloc know the old block size)
 * -------------------------------------------------------------------------- */
typedef struct { unsigned int size; unsigned int magic; } AllocHdr;
#define ALLOC_MAGIC 0xCAFEF00DU

static void* wrap_alloc(unsigned int size) {
    crt_malloc_count++;
    crt_malloc_last_size = size;
    AllocHdr* h = (AllocHdr*)imgui_c_alloc(size + sizeof(AllocHdr));
    if (!h) {
        console_writestring("[CRT] malloc FAILED size=");
        /* quick decimal print */
        char buf[12]; int i = 10; buf[11] = '\0';
        unsigned int v = size;
        do { buf[i--] = '0' + (v % 10); v /= 10; } while (v && i >= 0);
        console_writestring(&buf[i+1]);
        console_writestring("\r\n");
        return (void*)0;
    }
    h->size  = size;
    h->magic = ALLOC_MAGIC;
    return (void*)(h + 1);
}
static void wrap_free(void* ptr) {
    if (!ptr) return;
    imgui_c_free((AllocHdr*)ptr - 1);
}

/* --------------------------------------------------------------------------
 * Memory functions
 * -------------------------------------------------------------------------- */
void* memcpy(void* dst, const void* src, size_t n) {
    char* d = (char*)dst;
    const char* s = (const char*)src;
    while (n--) *d++ = *s++;
    return dst;
}

void* memset(void* dst, int c, size_t n) {
    unsigned char* d = (unsigned char*)dst;
    unsigned char  v = (unsigned char)c;
    while (n--) *d++ = v;
    return dst;
}

void* memmove(void* dst, const void* src, size_t n) {
    char* d = (char*)dst;
    const char* s = (const char*)src;
    if (d < s || d >= s + n)
        return memcpy(dst, src, n);
    d += n; s += n;
    while (n--) *--d = *--s;
    return dst;
}

int memcmp(const void* a, const void* b, size_t n) {
    const unsigned char* p = (const unsigned char*)a;
    const unsigned char* q = (const unsigned char*)b;
    while (n--) { if (*p != *q) return *p - *q; p++; q++; }
    return 0;
}

void* memchr(const void* s, int c, size_t n) {
    const unsigned char* p = (const unsigned char*)s;
    unsigned char v = (unsigned char)c;
    while (n--) { if (*p == v) return (void*)p; p++; }
    return (void*)0;
}

/* --------------------------------------------------------------------------
 * String functions
 * -------------------------------------------------------------------------- */
size_t strlen(const char* s) {
    const char* p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

size_t strnlen(const char* s, size_t maxlen) {
    size_t i = 0;
    while (i < maxlen && s[i]) i++;
    return i;
}

char* strcpy(char* dst, const char* src) {
    char* d = dst;
    while ((*d++ = *src++));
    return dst;
}

char* strncpy(char* dst, const char* src, size_t n) {
    char* d = dst;
    while (n-- && (*d++ = *src++));
    while (n--) *d++ = '\0';
    return dst;
}

char* strcat(char* dst, const char* src) {
    char* d = dst + strlen(dst);
    while ((*d++ = *src++));
    return dst;
}

char* strncat(char* dst, const char* src, size_t n) {
    char* d = dst + strlen(dst);
    while (n-- && *src) *d++ = *src++;
    *d = '\0';
    return dst;
}

int strcmp(const char* a, const char* b) {
    while (*a && (*a == *b)) { a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}

int strncmp(const char* a, const char* b, size_t n) {
    while (n-- && *a && (*a == *b)) { a++; b++; }
    if (!n) return 0;
    return (unsigned char)*a - (unsigned char)*b;
}

char* strstr(const char* hay, const char* needle) {
    size_t nl = strlen(needle);
    if (!nl) return (char*)hay;
    for (; *hay; hay++)
        if (!strncmp(hay, needle, nl)) return (char*)hay;
    return (void*)0;
}

char* strchr(const char* s, int c) {
    while (*s) { if (*s == (char)c) return (char*)s; s++; }
    return (c == '\0') ? (char*)s : (void*)0;
}

char* strrchr(const char* s, int c) {
    const char* last = (void*)0;
    while (*s) { if (*s == (char)c) last = s; s++; }
    if (c == '\0') return (char*)s;
    return (char*)last;
}

char* strdup(const char* s) {
    size_t n = strlen(s) + 1;
    char* p = (char*)wrap_alloc((unsigned int)n);
    if (p) memcpy(p, s, n);
    return p;
}

int strcasecmp(const char* a, const char* b) {
    while (*a && *b) {
        unsigned char ca = *a >= 'A' && *a <= 'Z' ? *a + 32 : (unsigned char)*a;
        unsigned char cb = *b >= 'A' && *b <= 'Z' ? *b + 32 : (unsigned char)*b;
        if (ca != cb) return ca - cb;
        a++; b++;
    }
    return (unsigned char)*a - (unsigned char)*b;
}

int strncasecmp(const char* a, const char* b, size_t n) {
    while (n-- && *a && *b) {
        unsigned char ca = *a >= 'A' && *a <= 'Z' ? *a + 32 : (unsigned char)*a;
        unsigned char cb = *b >= 'A' && *b <= 'Z' ? *b + 32 : (unsigned char)*b;
        if (ca != cb) return ca - cb;
        a++; b++;
    }
    if (!n) return 0;
    return (unsigned char)*a - (unsigned char)*b;
}

/* --------------------------------------------------------------------------
 * Heap functions
 * -------------------------------------------------------------------------- */
void* malloc(size_t size)           { return wrap_alloc((unsigned int)size); }
void  free(void* ptr)               { wrap_free(ptr); }

void* calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void* p = wrap_alloc((unsigned int)total);
    if (p) memset(p, 0, total);
    return p;
}

void* realloc(void* ptr, size_t new_size) {
    if (!ptr)      return wrap_alloc((unsigned int)new_size);
    if (!new_size) { wrap_free(ptr); return (void*)0; }
    AllocHdr* h = (AllocHdr*)ptr - 1;
    unsigned int old_size = (h->magic == ALLOC_MAGIC) ? h->size : 0;
    void* np = wrap_alloc((unsigned int)new_size);
    if (!np) return (void*)0;
    size_t copy = (old_size < (unsigned int)new_size) ? old_size : new_size;
    if (copy) memcpy(np, ptr, copy);
    wrap_free(ptr);
    return np;
}

/* --------------------------------------------------------------------------
 * Math  (i386 x87 intrinsics)
 * -------------------------------------------------------------------------- */
float sqrtf(float x)  { float r; __asm__("fsqrt" : "=t"(r) : "0"(x)); return r; }
float fabsf(float x)  { float r; __asm__("fabs"  : "=t"(r) : "0"(x)); return r; }
float sinf(float x)   { float r; __asm__("fsin"  : "=t"(r) : "0"(x)); return r; }
float cosf(float x)   { float r; __asm__("fcos"  : "=t"(r) : "0"(x)); return r; }
float tanf(float x)   { return sinf(x) / cosf(x); }

float atan2f(float y, float x) {
    float r;
    __asm__("fpatan" : "=t"(r) : "0"(x), "u"(y) : "st(1)");
    return r;
}

float acosf(float x)  { return atan2f(sqrtf(1.0f - x * x), x); }
float asinf(float x)  { return atan2f(x, sqrtf(1.0f - x * x)); }
float atanf(float x)  { return atan2f(x, 1.0f); }

float floorf(float x) {
    float r;
    unsigned short cw, cw_floor;
    __asm__("fstcw %0" : "=m"(cw));
    cw_floor = (cw & 0xF3FFU) | 0x0400U; /* round toward -inf */
    __asm__("fldcw %0" :: "m"(cw_floor));
    __asm__("frndint" : "=t"(r) : "0"(x));
    __asm__("fldcw %0" :: "m"(cw));
    return r;
}

float ceilf(float x) {
    float r;
    unsigned short cw, cw_up;
    __asm__("fstcw %0" : "=m"(cw));
    cw_up = (cw & 0xF3FFU) | 0x0800U; /* round toward +inf */
    __asm__("fldcw %0" :: "m"(cw_up));
    __asm__("frndint" : "=t"(r) : "0"(x));
    __asm__("fldcw %0" :: "m"(cw));
    return r;
}

float truncf(float x) {
    float r;
    unsigned short cw, cw_trunc;
    __asm__("fstcw %0" : "=m"(cw));
    cw_trunc = (cw & 0xF3FFU) | 0x0C00U; /* round toward zero */
    __asm__("fldcw %0" :: "m"(cw_trunc));
    __asm__("frndint" : "=t"(r) : "0"(x));
    __asm__("fldcw %0" :: "m"(cw));
    return r;
}

float roundf(float x) {
    return (x >= 0.0f) ? floorf(x + 0.5f) : ceilf(x - 0.5f);
}

float fmodf(float x, float y) {
    if (y == 0.0f) return 0.0f;
    return x - truncf(x / y) * y;
}

/* log2(x) via FYL2X: st(0) = 1.0, st(1) = x  ->  st(0) = log2(x) */
static float log2f_impl(float x) {
    float r, one = 1.0f;
    __asm__("fyl2x" : "=t"(r) : "0"(x), "u"(one) : "st(1)");
    return r;
}

/* 2^x via F2XM1 + FSCALE; x must be in range for accurate results */
static float exp2f_impl(float x) {
    float intpart, fracpart, r, two = 2.0f;
    intpart  = floorf(x);
    fracpart = x - intpart;
    /* F2XM1: computes 2^x - 1 for x in [-1, 1] */
    float tmp;
    __asm__("f2xm1" : "=t"(tmp) : "0"(fracpart));
    tmp += 1.0f;
    __asm__("fscale" : "=t"(r) : "0"(tmp), "u"(intpart) : "st(1)");
    return r;
}

static const float LN2 = 0.6931471805599453f;

float logf(float x)  { return log2f_impl(x) * LN2; }
float expf(float x)  { return exp2f_impl(x * (1.0f / LN2)); }

float powf(float x, float y) {
    if (x <= 0.0f) return 0.0f;
    return expf(y * logf(x));
}

double sqrt(double x)  { return (double)sqrtf((float)x); }
double fabs(double x)  { return (double)fabsf((float)x); }
double floor(double x) { return (double)floorf((float)x); }
double ceil(double x)  { return (double)ceilf((float)x); }
double fmod(double x, double y) { return (double)fmodf((float)x,(float)y); }
double sin(double x)   { return (double)sinf((float)x); }
double cos(double x)   { return (double)cosf((float)x); }
double acos(double x)  { return (double)acosf((float)x); }
double asin(double x)  { return (double)asinf((float)x); }
double atan(double x)  { return (double)atanf((float)x); }
double atan2(double y, double x) { return (double)atan2f((float)y,(float)x); }
double log(double x)   { return (double)logf((float)x); }
double exp(double x)   { return (double)expf((float)x); }
double pow(double x, double y)   { return (double)powf((float)x,(float)y); }

/* sincosf: GCC may optimise paired sinf+cosf calls into a single sincosf */
void sincosf(float x, float* s, float* c) { *s = sinf(x); *c = cosf(x); }
void sincos(double x, double* s, double* c) { *s = sin(x); *c = cos(x); }

int abs(int x)  { return x < 0 ? -x : x; }
long labs(long x) { return x < 0 ? -x : x; }

/* --------------------------------------------------------------------------
 * Number / string conversions
 * -------------------------------------------------------------------------- */
int atoi(const char* s) {
    while (*s == ' ' || *s == '\t') s++;
    int sign = 1, val = 0;
    if (*s == '-') { sign = -1; s++; } else if (*s == '+') s++;
    while (*s >= '0' && *s <= '9') val = val * 10 + (*s++ - '0');
    return sign * val;
}

long atol(const char* s) { return (long)atoi(s); }

long strtol(const char* s, char** end, int base) {
    while (*s == ' ' || *s == '\t') s++;
    int sign = 1;
    if (*s == '-') { sign = -1; s++; } else if (*s == '+') s++;
    if ((base == 0 || base == 16) && s[0] == '0' && (s[1]=='x'||s[1]=='X')) { s += 2; base = 16; }
    else if (base == 0 && s[0] == '0') base = 8;
    else if (base == 0) base = 10;
    long val = 0;
    while (1) {
        int d;
        if (*s >= '0' && *s <= '9')      d = *s - '0';
        else if (*s >= 'a' && *s <= 'z') d = *s - 'a' + 10;
        else if (*s >= 'A' && *s <= 'Z') d = *s - 'A' + 10;
        else break;
        if (d >= base) break;
        val = val * base + d;
        s++;
    }
    if (end) *end = (char*)s;
    return sign * val;
}

unsigned long strtoul(const char* s, char** end, int base) {
    return (unsigned long)strtol(s, end, base);
}

double strtod(const char* s, char** end) {
    while (*s == ' ' || *s == '\t') s++;
    double sign = 1.0, val = 0.0, frac = 1.0;
    if (*s == '-') { sign = -1.0; s++; } else if (*s == '+') s++;
    while (*s >= '0' && *s <= '9') val = val * 10.0 + (*s++ - '0');
    if (*s == '.') {
        s++;
        while (*s >= '0' && *s <= '9') { frac /= 10.0; val += (*s++ - '0') * frac; }
    }
    if (*s == 'e' || *s == 'E') {
        s++;
        int esign = 1, exp = 0;
        if (*s == '-') { esign = -1; s++; } else if (*s == '+') s++;
        while (*s >= '0' && *s <= '9') exp = exp * 10 + (*s++ - '0');
        double mult = 1.0;
        while (exp-- > 0) mult *= 10.0;
        if (esign > 0) val *= mult; else val /= mult;
    }
    if (end) *end = (char*)s;
    return sign * val;
}

float strtof(const char* s, char** end) { return (float)strtod(s, end); }

/* --------------------------------------------------------------------------
 * vsnprintf  (supports %d %i %u %x %X %o %f %e %E %g %G %s %c %p %% + flags/width/precision/length)
 * -------------------------------------------------------------------------- */

/* Write a single character into the output buffer with bounds check */
#define PUTC(c) do { if (pos < n-1) buf[pos] = (c); pos++; } while(0)

/* reverse a substring in-place */
static void reverse_str(char* s, int len) {
    int i = 0, j = len - 1;
    while (i < j) { char t = s[i]; s[i] = s[j]; s[j] = t; i++; j--; }
}

/* unsigned 64-bit integer to string, returns length */
static int u64_to_str(unsigned long long v, char* out, int base, int upper) {
    static const char* digits_lo = "0123456789abcdef";
    static const char* digits_up = "0123456789ABCDEF";
    const char* digits = upper ? digits_up : digits_lo;
    int len = 0;
    if (!v) { out[len++] = '0'; } else {
        while (v) { out[len++] = digits[v % (unsigned)base]; v /= (unsigned)base; }
    }
    reverse_str(out, len);
    out[len] = '\0';
    return len;
}

/* float to string: mode 'f','e','g'; returns length written into buf */
static int ftoa(double v, char* buf, int prec, char mode) {
    int len = 0;
    int neg = 0;
    if (v < 0.0) { neg = 1; v = -v; }

    /* handle nan / inf */
    if (v != v) { const char* s = "nan"; while (*s) buf[len++]=*s++; buf[len]=0; return len; }
    double huge = 1e38;
    if (v > huge) { if (neg) buf[len++]='-'; const char* s="inf"; while(*s) buf[len++]=*s++; buf[len]=0; return len; }

    if (prec < 0) prec = 6;
    if (prec > 20) prec = 20;

    /* determine exponent for 'e'/'g' */
    int exponent = 0;
    double vv = v;
    if (vv != 0.0) {
        while (vv >= 10.0) { vv /= 10.0; exponent++; }
        while (vv > 0.0 && vv < 1.0) { vv *= 10.0; exponent--; }
    }

    char eff_mode = mode;
    if (mode == 'g' || mode == 'G') {
        int use_e_form = (exponent < -4 || exponent >= prec);
        eff_mode = use_e_form ? (mode == 'G' ? 'E' : 'e') : 'f';
        if (!use_e_form && prec > 0) prec = prec - 1 - exponent;
        if (prec < 0) prec = 0;
    }

    if (neg) buf[len++] = '-';

    if (eff_mode == 'e' || eff_mode == 'E') {
        /* normalise to 1 <= vv < 10 */
        double mant = (v != 0.0) ? v / pow(10.0, exponent) : 0.0;
        /* print mantissa with 'f' format, prec fractional digits */
        /* integer part (always 1 digit for normalised) */
        unsigned long long ipart = (unsigned long long)mant;
        double fpart = mant - (double)ipart;
        char tmp[32]; int tl = u64_to_str(ipart, tmp, 10, 0);
        for (int i = 0; i < tl; i++) buf[len++] = tmp[i];
        if (prec > 0) {
            buf[len++] = '.';
            for (int i = 0; i < prec; i++) {
                fpart *= 10.0;
                int d = (int)fpart;
                if (d < 0) d = 0; if (d > 9) d = 9;
                buf[len++] = '0' + d;
                fpart -= d;
            }
        }
        buf[len++] = (eff_mode == 'E') ? 'E' : 'e';
        buf[len++] = (exponent >= 0) ? '+' : '-';
        if (exponent < 0) exponent = -exponent;
        if (exponent < 10) buf[len++] = '0';
        char et[8]; int el = u64_to_str((unsigned long long)exponent, et, 10, 0);
        for (int i = 0; i < el; i++) buf[len++] = et[i];
    } else {
        /* 'f' mode */
        /* Round the value to requested precision */
        double rounder = 0.5;
        for (int i = 0; i < prec; i++) rounder /= 10.0;
        v += rounder;
        unsigned long long ipart = (unsigned long long)v;
        double fpart = v - (double)ipart;
        char tmp[64]; int tl = u64_to_str(ipart, tmp, 10, 0);
        for (int i = 0; i < tl; i++) buf[len++] = tmp[i];
        if (prec > 0) {
            buf[len++] = '.';
            for (int i = 0; i < prec; i++) {
                fpart *= 10.0;
                int d = (int)fpart;
                if (d < 0) d = 0; if (d > 9) d = 9;
                buf[len++] = '0' + d;
                fpart -= d;
            }
        }
        /* strip trailing zeros for 'g' */
        if (mode == 'g' || mode == 'G') {
            while (len > 0 && buf[len-1] == '0') len--;
            if (len > 0 && buf[len-1] == '.') len--;
        }
    }
    buf[len] = '\0';
    return len;
}

/* write 'pad_cnt' padding characters 'pc' */
static size_t emit_pad(char* buf, size_t pos, size_t n, char pc, int count) {
    while (count-- > 0) PUTC(pc);
    return pos;
}

int vsnprintf(char* buf, size_t n, const char* fmt, __builtin_va_list ap) {
    if (!buf || !n) return 0;
    size_t pos = 0;

    while (*fmt) {
        if (*fmt != '%') { PUTC(*fmt++); continue; }
        fmt++; /* skip '%' */

        /* --- Flags --- */
        int flag_left = 0, flag_plus = 0, flag_space = 0, flag_zero = 0, flag_hash = 0;
        while (1) {
            if (*fmt == '-')      { flag_left  = 1; fmt++; }
            else if (*fmt == '+') { flag_plus  = 1; fmt++; }
            else if (*fmt == ' ') { flag_space = 1; fmt++; }
            else if (*fmt == '0') { flag_zero  = 1; fmt++; }
            else if (*fmt == '#') { flag_hash  = 1; fmt++; }
            else break;
        }

        /* --- Width --- */
        int width = 0;
        if (*fmt == '*') { width = __builtin_va_arg(ap, int); if (width < 0) { flag_left = 1; width = -width; } fmt++; }
        else { while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0'); }

        /* --- Precision --- */
        int prec = -1;
        if (*fmt == '.') {
            fmt++; prec = 0;
            if (*fmt == '*') { prec = __builtin_va_arg(ap, int); fmt++; }
            else { while (*fmt >= '0' && *fmt <= '9') prec = prec * 10 + (*fmt++ - '0'); }
        }

        /* --- Length modifier --- */
        int is_long = 0, is_longlong = 0, is_short = 0, is_char = 0;
        if (*fmt == 'l') {
            fmt++;
            if (*fmt == 'l') { is_longlong = 1; fmt++; } else is_long = 1;
        } else if (*fmt == 'h') {
            fmt++;
            if (*fmt == 'h') { is_char = 1; fmt++; } else is_short = 1;
        } else if (*fmt == 'z' || *fmt == 'j' || *fmt == 't') {
            is_long = 1; fmt++;
        }

        char conv = *fmt++;
        if (!conv) break;

        char tmp[128];
        int  tmp_len = 0;
        char prefix[4] = {0};
        int  prefix_len = 0;
        char sign_char = 0;

        switch (conv) {
        case '%':
            PUTC('%');
            continue;

        case 'c': {
            int c = __builtin_va_arg(ap, int);
            tmp[0] = (char)c; tmp_len = 1;
            break;
        }

        case 's': {
            const char* s = __builtin_va_arg(ap, const char*);
            if (!s) s = "(null)";
            tmp_len = (int)strlen(s);
            if (prec >= 0 && tmp_len > prec) tmp_len = prec;
            int pad = width - tmp_len;
            if (!flag_left && pad > 0) pos = emit_pad(buf, pos, n, ' ', pad);
            for (int k = 0; k < tmp_len; k++) PUTC(s[k]);
            if (flag_left && pad > 0) pos = emit_pad(buf, pos, n, ' ', pad);
            continue;
        }

        case 'd': case 'i': {
            long long v;
            if (is_longlong) v = __builtin_va_arg(ap, long long);
            else if (is_long) v = __builtin_va_arg(ap, long);
            else v = __builtin_va_arg(ap, int);
            if (is_short) v = (short)v;
            if (is_char)  v = (signed char)v;
            unsigned long long uv;
            if (v < 0) { sign_char = '-'; uv = (unsigned long long)(-v); }
            else { if (flag_plus) sign_char = '+'; else if (flag_space) sign_char = ' '; uv = (unsigned long long)v; }
            tmp_len = u64_to_str(uv, tmp, 10, 0);
            break;
        }

        case 'u': {
            unsigned long long uv;
            if (is_longlong) uv = __builtin_va_arg(ap, unsigned long long);
            else if (is_long) uv = __builtin_va_arg(ap, unsigned long);
            else uv = __builtin_va_arg(ap, unsigned int);
            if (is_short) uv = (unsigned short)uv;
            if (is_char)  uv = (unsigned char)uv;
            tmp_len = u64_to_str(uv, tmp, 10, 0);
            break;
        }

        case 'x': case 'X': {
            unsigned long long uv;
            if (is_longlong) uv = __builtin_va_arg(ap, unsigned long long);
            else if (is_long) uv = __builtin_va_arg(ap, unsigned long);
            else uv = __builtin_va_arg(ap, unsigned int);
            if (flag_hash && uv) { prefix[0]='0'; prefix[1]=(conv=='x'?'x':'X'); prefix_len=2; }
            tmp_len = u64_to_str(uv, tmp, 16, conv == 'X');
            break;
        }

        case 'o': {
            unsigned long long uv;
            if (is_longlong) uv = __builtin_va_arg(ap, unsigned long long);
            else uv = __builtin_va_arg(ap, unsigned int);
            if (flag_hash) { prefix[0]='0'; prefix_len=1; }
            tmp_len = u64_to_str(uv, tmp, 8, 0);
            break;
        }

        case 'p': {
            unsigned long uv = (unsigned long)__builtin_va_arg(ap, void*);
            prefix[0]='0'; prefix[1]='x'; prefix_len=2;
            tmp_len = u64_to_str((unsigned long long)uv, tmp, 16, 0);
            break;
        }

        case 'f': case 'F':
        case 'e': case 'E':
        case 'g': case 'G': {
            double v = __builtin_va_arg(ap, double);
            if (v < 0.0) { sign_char = '-'; v = -v; }
            else if (flag_plus) sign_char = '+';
            else if (flag_space) sign_char = ' ';
            char fmode = conv | 0x20; /* to lowercase */
            tmp_len = ftoa(v, tmp, prec < 0 ? 6 : prec, fmode);
            /* if ftoa added its own '-', don't double it */
            if (tmp[0] == '-') { sign_char = 0; }
            break;
        }

        case 'n': {
            int* p = __builtin_va_arg(ap, int*);
            if (p) *p = (int)pos;
            continue;
        }

        default:
            PUTC(conv);
            continue;
        }

        /* Apply precision (min digits) for integers */
        int prec_pad = 0;
        if (prec >= 0 && (conv == 'd' || conv == 'i' || conv == 'u' || conv == 'x' || conv == 'X' || conv == 'o'))
            prec_pad = prec - tmp_len;
        if (prec_pad < 0) prec_pad = 0;

        int total = tmp_len + prec_pad + prefix_len + (sign_char ? 1 : 0);
        int pad = width - total;
        if (pad < 0) pad = 0;

        char pad_char = (flag_zero && !flag_left && prec < 0) ? '0' : ' ';

        if (!flag_left) pos = emit_pad(buf, pos, n, ' ', pad);
        if (sign_char) PUTC(sign_char);
        for (int k = 0; k < prefix_len; k++) PUTC(prefix[k]);
        if (flag_zero && !flag_left) pos = emit_pad(buf, pos, n, '0', pad);
        pos = emit_pad(buf, pos, n, '0', prec_pad);
        for (int k = 0; k < tmp_len; k++) PUTC(tmp[k]);
        if (flag_left) pos = emit_pad(buf, pos, n, ' ', pad);
    }

    if (pos < n) buf[pos] = '\0';
    return (int)pos;
}

int snprintf(char* buf, size_t n, const char* fmt, ...) {
    int r;
    __builtin_va_list ap;
    __builtin_va_start(ap, fmt);
    r = vsnprintf(buf, n, fmt, ap);
    __builtin_va_end(ap);
    return r;
}

int sprintf(char* buf, const char* fmt, ...) {
    int r;
    __builtin_va_list ap;
    __builtin_va_start(ap, fmt);
    r = vsnprintf(buf, (size_t)4096, fmt, ap);
    __builtin_va_end(ap);
    return r;
}

/* printf: discard output (no console from this layer) */
int printf(const char* fmt, ...) { (void)fmt; return 0; }

/* putchar / putc: discard (fputc, fputs, fwrite, fprintf, fflush, stderr
   are now in imgbridge.c which has proper hosted FILE* types) */
typedef struct { int _dummy; } FILE;
int putchar(int c) { return c; }
int putc(int c, FILE* f) { (void)f; return c; }

/* --------------------------------------------------------------------------
 * Process / abort
 * -------------------------------------------------------------------------- */
void abort(void) { for (;;) __asm__("cli; hlt"); }
void exit(int code) { (void)code; abort(); }

/* --------------------------------------------------------------------------
 * Assert  — print to serial via console_writestring before halting
 * -------------------------------------------------------------------------- */
static void _assert_print_dec(int v) {
    char buf[12]; int i = 10; buf[11] = '\0';
    unsigned int u = (v < 0) ? (unsigned int)(-v) : (unsigned int)v;
    do { buf[i--] = '0' + (u % 10); u /= 10; } while (u && i >= 0);
    if (v < 0) buf[i--] = '-';
    console_writestring(&buf[i+1]);
}
void __assert_fail(const char* expr, const char* file, int line, const char* func) {
    console_writestring("[ASSERT FAIL] ");
    if (file) { console_writestring(file); console_writestring(":"); }
    _assert_print_dec(line);
    console_writestring(" in ");
    if (func) console_writestring(func);
    console_writestring(": ");
    if (expr) console_writestring(expr);
    console_writestring("\r\n");
    abort();
}

/* --------------------------------------------------------------------------
 * C++ ABI stubs
 * -------------------------------------------------------------------------- */
void __cxa_pure_virtual(void) { abort(); }

int __cxa_atexit(void (*func)(void*), void* arg, void* dso) {
    (void)func; (void)arg; (void)dso;
    return 0;
}

int atexit(void (*func)(void)) { (void)func; return 0; }

/* Guard variables for local static initialisation (single-threaded) */
typedef struct { unsigned char lock; } __cxa_guard_t;
int  __cxa_guard_acquire(__cxa_guard_t* g) { return !g->lock; }
void __cxa_guard_release(__cxa_guard_t* g) { g->lock = 1; }
void __cxa_guard_abort  (__cxa_guard_t* g) { (void)g; }

/* operator new / delete (bare-bones; ImGui overrides them via IM_MALLOC anyway) */
void* __builtin_new       (size_t sz)  { return wrap_alloc((unsigned int)sz); }
void* __builtin_vec_new   (size_t sz)  { return wrap_alloc((unsigned int)sz); }
void  __builtin_delete    (void* p)    { wrap_free(p); }
void  __builtin_vec_delete(void* p)    { wrap_free(p); }

/* Weak aliases so both mangled and plain names resolve */
void* _Znwj  (unsigned int sz) __attribute__((alias("__builtin_new")));
void* _Znaj  (unsigned int sz) __attribute__((alias("__builtin_new")));
void  _ZdlPv (void* p)         __attribute__((alias("__builtin_delete")));
void  _ZdaPv (void* p)         __attribute__((alias("__builtin_delete")));

/* for <new> nothrow variants */
void* _ZnwjRKSt9nothrow_t(unsigned int sz, void* nt)
    { (void)nt; return wrap_alloc(sz); }
void* _ZnajRKSt9nothrow_t(unsigned int sz, void* nt)
    { (void)nt; return wrap_alloc(sz); }

/* --------------------------------------------------------------------------
 * Misc POSIX / stdio stubs ImGui may reference
 * -------------------------------------------------------------------------- */
int isdigit(int c)  { return c >= '0' && c <= '9'; }
int isalpha(int c)  { return (c>='a'&&c<='z')||(c>='A'&&c<='Z'); }
int isupper(int c)  { return c >= 'A' && c <= 'Z'; }
int islower(int c)  { return c >= 'a' && c <= 'z'; }
int isspace(int c)  { return c==' '||c=='\t'||c=='\n'||c=='\r'||c=='\f'||c=='\v'; }
int isprint(int c)  { return c >= 0x20 && c < 0x7F; }
int isgraph(int c)  { return c > 0x20 && c < 0x7F; }
int isalnum(int c)  { return isdigit(c) || isalpha(c); }
int toupper(int c)  { return (c>='a'&&c<='z') ? c-32 : c; }
int tolower(int c)  { return (c>='A'&&c<='Z') ? c+32 : c; }

/* qsort (simple insertion sort — ImGui uses it only rarely for small arrays) */
void qsort(void* base, size_t nmemb, size_t size, int(*cmp)(const void*,const void*)) {
    char* b = (char*)base;
    char* tmp = (char*)wrap_alloc((unsigned int)size);
    if (!tmp) return;
    for (size_t i = 1; i < nmemb; i++) {
        memcpy(tmp, b + i*size, size);
        size_t j = i;
        while (j > 0 && cmp(b + (j-1)*size, tmp) > 0) {
            memcpy(b + j*size, b + (j-1)*size, size);
            j--;
        }
        memcpy(b + j*size, tmp, size);
    }
    wrap_free(tmp);
}

/* --------------------------------------------------------------------------
 * GCC stack protector / hardened-function stubs
 * These should never fire because we compile with -fno-stack-protector
 * and -D_FORTIFY_SOURCE=0, but the linker may still reference them
 * from translation units compiled without those flags.
 * -------------------------------------------------------------------------- */
unsigned long __stack_chk_guard = 0xDEADBEEF;
void __stack_chk_fail(void)       { for(;;); }
void __stack_chk_fail_local(void) { for(;;); }
void* __memset_chk(void* dst, int c, size_t len, size_t dstlen) {
    (void)dstlen;
    return memset(dst, c, len);
}
void* __memcpy_chk(void* dst, const void* src, size_t len, size_t dstlen) {
    (void)dstlen;
    return memcpy(dst, src, len);
}

/* --------------------------------------------------------------------------
 * sscanf  (minimal: only handles %d, %x, %f – enough for ImGui .ini
 *          table-settings parsing)
 * -------------------------------------------------------------------------- */
typedef __builtin_va_list va_list;
#define va_start(v,l) __builtin_va_start(v,l)
#define va_arg(v,t)   __builtin_va_arg(v,t)
#define va_end(v)     __builtin_va_end(v)

static int _is_space(char c) { return c==' '||c=='\t'||c=='\n'||c=='\r'; }
static int _is_digit(char c) { return c>='0' && c<='9'; }
static int _hex_val(char c) {
    if (c>='0'&&c<='9') return c-'0';
    if (c>='a'&&c<='f') return c-'a'+10;
    if (c>='A'&&c<='F') return c-'A'+10;
    return -1;
}

int vsscanf(const char* str, const char* fmt, va_list ap) {
    int matched = 0;
    const char* s = str;
    while (*fmt) {
        if (*fmt == '%') {
            fmt++;
            /* skip width (not needed for ImGui) */
            while (_is_digit(*fmt)) fmt++;
            if (*fmt == 'd' || *fmt == 'i') {
                fmt++;
                while (_is_space(*s)) s++;
                int neg = 0; long val = 0;
                if (*s == '-') { neg = 1; s++; }
                else if (*s == '+') s++;
                if (!_is_digit(*s)) break;
                while (_is_digit(*s)) { val = val * 10 + (*s - '0'); s++; }
                int* out = va_arg(ap, int*);
                *out = neg ? -(int)val : (int)val;
                matched++;
            } else if (*fmt == 'x' || *fmt == 'X') {
                fmt++;
                while (_is_space(*s)) s++;
                if (s[0]=='0' && (s[1]=='x'||s[1]=='X')) s += 2;
                unsigned long val = 0;
                if (_hex_val(*s) < 0) break;
                while (_hex_val(*s) >= 0) { val = val * 16 + _hex_val(*s); s++; }
                unsigned int* out = va_arg(ap, unsigned int*);
                *out = (unsigned int)val;
                matched++;
            } else if (*fmt == 'f') {
                fmt++;
                while (_is_space(*s)) s++;
                int neg = 0; float val = 0.0f; float frac = 0.1f;
                if (*s == '-') { neg = 1; s++; }
                else if (*s == '+') s++;
                while (_is_digit(*s)) { val = val * 10.0f + (*s - '0'); s++; }
                if (*s == '.') { s++; while (_is_digit(*s)) { val += (*s - '0') * frac; frac *= 0.1f; s++; } }
                float* out = va_arg(ap, float*);
                *out = neg ? -val : val;
                matched++;
            } else {
                break; /* unsupported conversion */
            }
        } else if (_is_space(*fmt)) {
            fmt++;
            while (_is_space(*s)) s++;
        } else {
            if (*s != *fmt) break;
            s++; fmt++;
        }
    }
    return matched;
}

int sscanf(const char* str, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vsscanf(str, fmt, ap);
    va_end(ap);
    return r;
}

/* GCC 14+ may emit calls to __isoc23_sscanf instead of sscanf */
int __isoc23_sscanf(const char* str, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vsscanf(str, fmt, ap);
    va_end(ap);
    return r;
}

/* Needed by GCC internal calls on i386 */
long long __divdi3 (long long a, long long b) { return a/b; }
long long __moddi3 (long long a, long long b) { return a%b; }
unsigned long long __udivdi3(unsigned long long a, unsigned long long b) { return a/b; }

/* --------------------------------------------------------------------------
 * glibc ctype locale stubs
 * __ctype_toupper_loc returns a pointer-to-pointer-to-int table (384 entries,
 * indexed [-128..255]).  We provide a minimal ASCII-only toupper table.
 * -------------------------------------------------------------------------- */
static const int _toupper_table[384] = {
    /* -128 .. -1 : identity (high-byte chars pass through) */
    128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,
    144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,
    160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,
    176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,
    192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,
    208,209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,
    224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,
    240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255,
    /* 0 .. 127 : ASCII toupper */
      0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
     32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
     48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
     64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
     80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
     96, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,  /* a-z -> A-Z */
     80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90,123,124,125,126,127,
    /* 128 .. 255 : identity */
    128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,
    144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,
    160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,
    176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,
    192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,
    208,209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,
    224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,
    240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255
};
/* Pointer starts at element [128] so that index -128 maps to table[0] */
static const int* _toupper_ptr = &_toupper_table[128];
const int** __ctype_toupper_loc(void) { return &_toupper_ptr; }

/* Provide tolower loc too in case it's needed */
static const int _tolower_table[384] = {
    /* -128 .. -1 : identity */
    128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,
    144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,
    160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,
    176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,
    192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,
    208,209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,
    224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,
    240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255,
    /* 0 .. 127 : ASCII tolower */
      0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
     32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
     48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
     64, 97, 98, 99,100,101,102,103,104,105,106,107,108,109,110,111,  /* A-Z -> a-z */
    112,113,114,115,116,117,118,119,120,121,122, 91, 92, 93, 94, 95,
     96, 97, 98, 99,100,101,102,103,104,105,106,107,108,109,110,111,
    112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,
    /* 128 .. 255 : identity */
    128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,
    144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,
    160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,
    176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,
    192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,
    208,209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,
    224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,
    240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255
};
static const int* _tolower_ptr = &_tolower_table[128];
const int** __ctype_tolower_loc(void) { return &_tolower_ptr; }

/* glibc ctype b-table (character classification bitmask) */
static const unsigned short _ctype_b_table[384] = {0};
static const unsigned short* _ctype_b_ptr = &_ctype_b_table[128];
const unsigned short** __ctype_b_loc(void) { return &_ctype_b_ptr; }
unsigned long long __umoddi3(unsigned long long a, unsigned long long b) { return a%b; }
