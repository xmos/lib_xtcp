#if !defined(MBEDTLS_CONFIG_FILE)
#include "mbedtls/config.h"
#else
#include MBEDTLS_CONFIG_FILE
#endif

#include "mbedtls/ctr_drbg_xmos_wrap.h"
#include "random.h"

#include <string.h>

void mbedtls_ctr_drbg_init( random_generator_t *ctx )
{

}


int mbedtls_ctr_drbg_seed( random_generator_t *ctx,
                   void *p_entropy,
                   const unsigned char *custom,
                   size_t len )
{
    *ctx = random_create_generator_from_hw_seed();

    return 0;
}

int mbedtls_ctr_drbg_random( void *p_rng, unsigned char *output, size_t output_len )
{
    random_generator_t *ctx = (random_generator_t *) p_rng;

    random_get_random_bytes(ctx, output, output_len);

    return( 0 );
}