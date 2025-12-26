#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Objective-C wrapper for Opus encoder CTL operations
 * Provides a bridge between Swift and C variadic functions
 */
@interface OpusCtlHelpers : NSObject

/**
 * Set the encoder bitrate
 * @param encoder Pointer to OpusEncoder (as void*)
 * @param bitrate Bitrate in bits per second
 * @return OPUS_OK on success, or negative error code
 */
+ (int)setBitrate:(void *)encoder bitrate:(int)bitrate;

/**
 * Set DRED duration
 * @param encoder Pointer to OpusEncoder (as void*)
 * @param durationMs DRED duration in milliseconds (0-100)
 * @return OPUS_OK on success, or negative error code
 */
+ (int)setDredDuration:(void *)encoder durationMs:(int)durationMs;

/**
 * Set variable bitrate mode
 * @param encoder Pointer to OpusEncoder (as void*)
 * @param vbr 1 for VBR, 0 for CBR
 * @return OPUS_OK on success, or negative error code
 */
+ (int)setVbr:(void *)encoder vbr:(int)vbr;

/**
 * Set encoder complexity
 * @param encoder Pointer to OpusEncoder (as void*)
 * @param complexity Complexity (0-10)
 * @return OPUS_OK on success, or negative error code
 */
+ (int)setComplexity:(void *)encoder complexity:(int)complexity;

/**
 * Set inband FEC
 * @param encoder Pointer to OpusEncoder (as void*)
 * @param fec 1 to enable, 0 to disable
 * @return OPUS_OK on success, or negative error code
 */
+ (int)setInbandFec:(void *)encoder fec:(int)fec;

/**
 * Set DTX (discontinuous transmission)
 * @param encoder Pointer to OpusEncoder (as void*)
 * @param dtx 1 to enable, 0 to disable
 * @return OPUS_OK on success, or negative error code
 */
+ (int)setDtx:(void *)encoder dtx:(int)dtx;

@end

NS_ASSUME_NONNULL_END
