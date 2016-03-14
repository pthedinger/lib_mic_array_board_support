// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <xscope.h>
#include <platform.h>
#include <xs1.h>
#include <string.h>
#include <xclib.h>
#include <stdint.h>
#include "stdio.h"
#include <stdlib.h>
#include <math.h>

#include "mic_array.h"


//If the decimation factor is changed the the coefs array of decimator_config must also be changed.
#define DECIMATION_FACTOR   2   //Corresponds to a 48kHz output sample rate
#define DECIMATOR_COUNT     2   //8 channels requires 2 decimators
#define FRAME_BUFFER_COUNT  2   //The minimum of 2 will suffice for this example

on tile[0]: in port p_pdm_clk               = XS1_PORT_1E;
on tile[0]: in buffered port:32 p_pdm_mics  = XS1_PORT_8B;
on tile[0]: in port p_mclk                  = XS1_PORT_1F;
on tile[0]: clock pdmclk                    = XS1_CLKBLK_1;


int data[8][THIRD_STAGE_COEFS_PER_STAGE*DECIMATION_FACTOR];

void test(streaming chanend c_ds_output[DECIMATOR_COUNT]) {
    unsafe{
        unsigned buffer;
        memset(data, 0, 8*THIRD_STAGE_COEFS_PER_STAGE*DECIMATION_FACTOR*sizeof(int));

        mic_array_frame_time_domain audio[FRAME_BUFFER_COUNT];

        mic_array_decimator_conf_common_t dcc = {0, 1, 0, 0, DECIMATION_FACTOR,
               g_third_stage_div_2_fir, 0, FIR_COMPENSATOR_DIV_2,
               DECIMATOR_NO_FRAME_OVERLAP, FRAME_BUFFER_COUNT};
        mic_array_decimator_config_t dc[2] = {
          {&dcc, data[0], {INT_MAX, INT_MAX, INT_MAX, INT_MAX}, 4},
          {&dcc, data[4], {INT_MAX, INT_MAX, INT_MAX, INT_MAX}, 4}
        };

        mic_array_decimator_configure(c_ds_output, DECIMATOR_COUNT, dc);

        mic_array_init_time_domain_frame(c_ds_output, DECIMATOR_COUNT, buffer, audio, dc);

        for(unsigned i=0;i<4096;i++)
            mic_array_get_next_time_domain_frame(c_ds_output, DECIMATOR_COUNT, buffer, audio, dc);

        long long avg [7] = {0};
#define R 16
#define REPS (1<<R)

        for(unsigned r=0;r<REPS;r++){

            mic_array_frame_time_domain *  current =
                               mic_array_get_next_time_domain_frame(c_ds_output, DECIMATOR_COUNT, buffer, audio, dc);


            for(unsigned m=0;m<7;m++){
                long long energy = 0;
                for(unsigned s=0;s<(1<<MIC_ARRAY_MAX_FRAME_SIZE_LOG2);s++){

                    long long v = current->data[m][s];
                    v=v>>((MIC_ARRAY_MAX_FRAME_SIZE_LOG2)/2);
                    energy += (v*v);
                }
                avg[m] += (energy/REPS);
            }

        }

        long long overall_average = 0;

        for(unsigned m=0;m<7;m++)
            overall_average += (avg[m]/7);

        long long min = LONG_LONG_MAX;
        long long max = LONG_LONG_MIN;


        for(unsigned m=0;m<7;m++){
            if(min > avg[m]) min = avg[m];
            if(max < avg[m]) max = avg[m];
        }

        long long diff = max - min;
        printf("Microphone gain spread = %fdB\n",0.5* 20.0 * log10((double)min / (double)(max)));

        int all_work = 0;
        for(unsigned m=0;m<7;m++){
            if((overall_average/avg[m]) < 2){
            } else {
                all_work = 1;
            }
        }
        if(all_work == 0)
            printf("All microphones working\n");
        else
            printf("At least one microphone broken\n");
        delay_milliseconds(100);
        _Exit(all_work);
    }
}

int main() {

    par {
        on tile[0]:{
            configure_clock_ref(pdmclk, 18);
            configure_port_clock_output(p_pdm_clk, pdmclk);
            configure_in_port(p_pdm_mics, pdmclk);
            start_clock(pdmclk);

            streaming chan c_4x_pdm_mic[DECIMATOR_COUNT];
            streaming chan c_ds_output[DECIMATOR_COUNT];

            par {
                mic_array_pdm_rx(p_pdm_mics, c_4x_pdm_mic[0], c_4x_pdm_mic[1]);
                mic_array_decimate_to_pcm_4ch(c_4x_pdm_mic[0], c_ds_output[0]);
                mic_array_decimate_to_pcm_4ch(c_4x_pdm_mic[1], c_ds_output[1]);
                test(c_ds_output);
            }

        }

    }
    return 0;
}
