#ifndef OPUS_CTL_HELPERS_H
#define OPUS_CTL_HELPERS_H

#include "opus.h"

/**
 * C helper functions for opus_encoder_ctl operations
 *
 * Swift cannot call variadic C functions like opus_encoder_ctl directly.
 * These non-variadic wrapper functions allow Swift to configure the Opus encoder.
 */

/**
 * Set the encoder's bitrate
 * @param enc Opus encoder instance
 * @param bitrate Target bitrate in bits/second (e.g., 24000 for 24kbps)
 * @return OPUS_OK on success, error code otherwise
 */
int opus_encoder_ctl_set_bitrate(OpusEncoder *enc, opus_int32 bitrate);

/**
 * Set the DRED (Deep Redundancy) duration
 * @param enc Opus encoder instance
 * @param duration_ms DRED recovery duration in milliseconds (e.g., 100)
 * @return OPUS_OK on success, error code otherwise
 */
int opus_encoder_ctl_set_dred_duration(OpusEncoder *enc, opus_int32 duration_ms);

/**
 * Enable/disable variable bitrate (VBR)
 * @param enc Opus encoder instance
 * @param vbr 1 to enable VBR, 0 for constant bitrate (CBR)
 * @return OPUS_OK on success, error code otherwise
 */
int opus_encoder_ctl_set_vbr(OpusEncoder *enc, opus_int32 vbr);

/**
 * Set encoding complexity (0-10)
 * @param enc Opus encoder instance
 * @param complexity Complexity level: 0 (lowest CPU) to 10 (highest quality)
 * @return OPUS_OK on success, error code otherwise
 */
int opus_encoder_ctl_set_complexity(OpusEncoder *enc, opus_int32 complexity);

/**
 * Enable/disable in-band forward error correction (FEC)
 * @param enc Opus encoder instance
 * @param fec 1 to enable FEC, 0 to disable
 * @return OPUS_OK on success, error code otherwise
 */
int opus_encoder_ctl_set_inband_fec(OpusEncoder *enc, opus_int32 fec);

/**
 * Enable/disable discontinuous transmission (DTX)
 * @param enc Opus encoder instance
 * @param dtx 1 to enable DTX, 0 to disable
 * @return OPUS_OK on success, error code otherwise
 */
int opus_encoder_ctl_set_dtx(OpusEncoder *enc, opus_int32 dtx);

#endif // OPUS_CTL_HELPERS_H
