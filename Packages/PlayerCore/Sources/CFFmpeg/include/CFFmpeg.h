#ifndef CFFMPEG_H
#define CFFMPEG_H

#include <errno.h>
#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/dict.h>
#include <libavutil/dovi_meta.h>
#include <libavutil/error.h>
#include <libavutil/mastering_display_metadata.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>

// Macros Swift cannot import.
static inline int cff_averror_eagain(void) { return AVERROR(EAGAIN); }
static inline int cff_averror_eof(void) { return AVERROR_EOF; }
static inline int cff_averror_exit(void) { return AVERROR_EXIT; }
static inline int cff_averror_eio(void) { return AVERROR(EIO); }
static inline int cff_averror_invaliddata(void) { return AVERROR_INVALIDDATA; }
static inline int64_t cff_nopts_value(void) { return AV_NOPTS_VALUE; }
static inline int cff_avseek_size(void) { return AVSEEK_SIZE; }
static inline int cff_avseek_force(void) { return AVSEEK_FORCE; }

typedef int (*cff_io_open_fn)(struct AVFormatContext *s, AVIOContext **pb, const char *url, int flags,
                              AVDictionary **options);
typedef int (*cff_io_close2_fn)(struct AVFormatContext *s, AVIOContext *pb);

static inline void cff_set_io_callbacks(AVFormatContext *s, cff_io_open_fn open, cff_io_close2_fn close2) {
    s->io_open = open;
    s->io_close2 = close2;
}

static inline void cff_set_interrupt(AVFormatContext *s, int (*callback)(void *), void *opaque) {
    s->interrupt_callback.callback = callback;
    s->interrupt_callback.opaque = opaque;
}

#endif
