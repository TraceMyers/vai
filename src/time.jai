
Initialize_Time :: () {
    assert(DEBUG_SAMPLE_DELTA_TIME > FRAME_TIME_TARGET * 2.0);
    Sample_Frame_Time(false);
}

Sample_Frame_Time :: (update_frame_counter := true) {
    frame_end := seconds_since_init();
    delta_time = max(frame_end - frame_start, 0.0);
    frame_start = frame_end;

    if frame_time_index >= frame_times.count {
        filled_buffer = true;
        frame_time_index = 0;
    }

    running_frame_times[running_frame_time_index] = delta_time;
    running_frame_time_index += 1;
    if running_frame_time_index >= running_frame_times.count {
        running_frame_time_index = 0;
    }
    running_average_frame_time = Calculate_Running_Average_Frame_Time();

    if delta_time > max_frame_time {
        max_frame_time = delta_time;
        dtimer_replace_max = MAX_REPLACE_DELAY;
    } else {
        if dtimer_replace_max <= 0.0 {
            max_frame_time = delta_time;
            dtimer_replace_max = MAX_REPLACE_DELAY;
        } else {
            dtimer_replace_max -= delta_time;
        }
    }

    store_time := true;
    if filled_buffer {
        utimer_sample += delta_time;    
        if utimer_sample >= DEBUG_SAMPLE_DELTA_TIME {
            // this doesn't necessarily clear the timer, but it will be more accurate that setting it to 0 in almost all cases
            utimer_sample -= DEBUG_SAMPLE_DELTA_TIME;
        } else {
            store_time = false;
        }
    }
    if store_time {
        frame_times[frame_time_index] = delta_time;
        frame_time_index += 1;
    }

    if update_frame_counter {
        frame_counter += 1;
    }
}

Smoothed_Delta_Time :: inline () -> float32 {
    return xx running_average_frame_time;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

FRAME_TIME_TARGET : float64 : 1.0 / 360.0;
DEBUG_SAMPLE_DELTA_TIME : float64 : 0.05;
MAX_REPLACE_DELAY :: 3.0;

frame_counter := 0;
delta_time: float64;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

Calculate_Running_Average_Frame_Time :: () -> float64 {
    sum: float64;
    for running_frame_times {
        sum += it;
    }
    return sum / xx running_frame_times.count;
}

frame_times: [128]float64;
max_frame_time: float64;
running_frame_times: [7]float64;
frame_time_index: s32;
running_average_frame_time: float64;
running_frame_time_index: s32;
frame_start: float64;
dtimer_replace_max: float64;
utimer_sample: float64;
filled_buffer: bool;
