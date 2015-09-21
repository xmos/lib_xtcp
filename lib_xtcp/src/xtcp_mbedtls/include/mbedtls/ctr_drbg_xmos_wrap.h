#ifndef MBEDTLS_CTR_DRBG_XMOS_WRAP_H
#define MBEDTLS_CTR_DRBG_XMOS_WRAP_H

#include "random.h"

#if defined(__cplusplus) || defined(__XC__)
extern "C" {
#endif

/**
 * \brief               CTR_DRBG context initialization
 *                      Makes the context ready for mbetls_ctr_drbg_seed() or
 *                      mbedtls_ctr_drbg_free().
 *
 * \param ctx           CTR_DRBG context to be initialized
 */
void mbedtls_ctr_drbg_init( random_generator_t *ctx );

/**
 * \brief               CTR_DRBG initial seeding
 *                      Seed and setup entropy source for future reseeds.
 *
 * Note: Personalization data can be provided in addition to the more generic
 *       entropy source to make this instantiation as unique as possible.
 *
 * \param ctx           CTR_DRBG context to be seeded
 * \param f_entropy     Entropy callback (p_entropy, buffer to fill, buffer
 *                      length)
 * \param p_entropy     Entropy context
 * \param custom        Personalization data (Device specific identifiers)
 *                      (Can be NULL)
 * \param len           Length of personalization data
 *
 * \return              0 if successful, or
 *                      MBEDTLS_ERR_CTR_DRBG_ENTROPY_SOURCE_FAILED
 */
int mbedtls_ctr_drbg_seed( random_generator_t *ctx,
                   void *p_entropy,
                   const unsigned char *custom,
                   size_t len );

/**
 * \brief               CTR_DRBG generate random
 *
 * Note: Automatically reseeds if reseed_counter is reached.
 *
 * \param p_rng         CTR_DRBG context
 * \param output        Buffer to fill
 * \param output_len    Length of the buffer
 *
 * \return              0 if successful, or
 *                      MBEDTLS_ERR_CTR_DRBG_ENTROPY_SOURCE_FAILED, or
 *                      MBEDTLS_ERR_CTR_DRBG_REQUEST_TOO_BIG
 */
int mbedtls_ctr_drbg_random( void *p_rng,
                     unsigned char *output, size_t output_len );

#if defined(__cplusplus) || defined(__XC__)
}
#endif

#endif /* ctr_drbg.h */
