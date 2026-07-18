
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

INTERACTIVE_DELTA_TIME_MAX :: 1.0 / 30.0;
INTERACTIVE_DELTA_TIME_HISTORY_COUNT :: 7;

Robust_Interactive_Delta_Time :: (samples: *[INTERACTIVE_DELTA_TIME_HISTORY_COUNT]float64, fallback: float64) -> float32 {
    sorted_samples: [INTERACTIVE_DELTA_TIME_HISTORY_COUNT]float64;
    sample_count: s32;
    for samples.* {
        if it <= 0 {
            continue;
        }
        sample := min(it, INTERACTIVE_DELTA_TIME_MAX);
        insert_index := sample_count;
        while insert_index > 0 && sorted_samples[insert_index-1] > sample {
            sorted_samples[insert_index] = sorted_samples[insert_index-1];
            insert_index -= 1;
        }
        sorted_samples[insert_index] = sample;
        sample_count += 1;
    }

    if sample_count == 0 {
        return clamp(cast(float32)fallback, 0.0, cast(float32)INTERACTIVE_DELTA_TIME_MAX);
    }

    // Preserve the original seven-frame average for ordinary frame jitter.
    // Samples far from the median are hitches rather than a useful pacing
    // signal, so replace only those outliers instead of letting one bad frame
    // contaminate the next seven animation steps.
    middle_index := sample_count / 2;
    median := sorted_samples[middle_index];
    if sample_count % 2 == 0 {
        median = (median + sorted_samples[middle_index-1]) * 0.5;
    }
    outlier_min := median * 0.5;
    outlier_max := median * 1.75;
    sum: float64;
    index: s32;
    while index < sample_count {
        sample := sorted_samples[index];
        if sample < outlier_min || sample > outlier_max {
            sample = median;
        }
        sum += sample;
        index += 1;
    }
    return cast(float32)(sum / cast(float64)sample_count);
}

Interactive_Delta_Time :: inline () -> float32 {
    return Robust_Interactive_Delta_Time(*running_frame_times, delta_time);
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
running_frame_times: [INTERACTIVE_DELTA_TIME_HISTORY_COUNT]float64;
frame_time_index: s32;
running_average_frame_time: float64;
running_frame_time_index: s32;
frame_start: float64;
dtimer_replace_max: float64;
utimer_sample: float64;
filled_buffer: bool;
