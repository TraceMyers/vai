
Thread_Worker :: struct  {

    Initialize :: () -> success: bool {
        next_tasks = *task_buffer_a;
        working_tasks = *task_buffer_b;
        thread_worker_should_run = true;
        thread_worker_should_work = false;
        thread_init(*thread_worker, Thread_Worker_Loop);
        thread_start(*thread_worker);
        return true;
    }

    Shutdown :: () {
        thread_worker_should_run = false;
        thread_worker_should_work = false;
        while !thread_is_done(*thread_worker, 1) {;}
        thread_deinit(*thread_worker);

        next_tasks = null;
        working_tasks = null;
        array_reset(*task_buffer_a);
        array_reset(*task_buffer_b);
    }

}

Thread_Worker_Loop :: (t: *Thread) -> s64 {
    while thread_worker_should_run {
        if thread_worker_should_work {
            for working_tasks.* {
                Init_Task_Result(*it);
                if it.request.type == {
                case .LOAD_FILE_EXPLORER_PREVIEW;
                    Load_File_Explorer_Preview(*it);
                case .LOAD_FILE_EXPLORER_IMAGE_PREVIEW;
                    Load_File_Explorer_Image_Preview(*it);
                }
                reset_temporary_storage();
            }
            thread_worker_should_work = false;
        }
        sleep_milliseconds(1);
    }
    Log("thread worker exit");
    return 0;
}

Init_Task_Result :: (task: *AsyncTask) {
    if #complete task.request.type == {
    case .SEARCH_TEXT;
    case .LOAD_FILE_EXPLORER_PREVIEW;
        task.result.load_file_explorer_preview = .{};
    case .LOAD_FILE_EXPLORER_IMAGE_PREVIEW;
        task.result.load_file_explorer_image_preview = .{};
    }
}

Load_File_Explorer_Preview :: (task: *AsyncTask) {
    file_path := task.request.load_file_explorer_preview.file_path;
    task.result.load_file_explorer_preview.success = Load_File_Into_Buffer(file_path, *file_explorer_text_preview, false);
}

Load_File_Explorer_Image_Preview :: (task: *AsyncTask) {
    file_path := task.request.load_file_explorer_image_preview.file_path;
    width, height, source_channels: s32;
    decoded_pixels := stbi_load(temp_c_string(file_path), *width, *height, *source_channels, 4);
    if decoded_pixels == null {
        return;
    }
    defer stbi_image_free(decoded_pixels);

    // Keep malformed or unexpectedly huge assets from exhausting the editor.
    MAX_PREVIEW_DIMENSION :: 16384;
    MAX_PREVIEW_BYTES :: 256 * 1024 * 1024;
    pixel_byte_count := cast(s64)width * cast(s64)height * 4;
    if width <= 0 || height <= 0
    || width > MAX_PREVIEW_DIMENSION || height > MAX_PREVIEW_DIMENSION
    || pixel_byte_count <= 0 || pixel_byte_count > MAX_PREVIEW_BYTES {
        return;
    }

    result := *task.result.load_file_explorer_image_preview;
    result.pixels = NewArray(pixel_byte_count, u8, initialized=false);
    memcpy(result.pixels.data, decoded_pixels, pixel_byte_count);
    result.width = width;
    result.height = height;
    result.success = true;
}

SearchTextRequest :: struct {
    find_pattern: string;
}

LoadFileExplorerPreviewRequest :: struct {
    file_path: string;
}

LoadFileExplorerPreviewResult :: struct {
    success: bool;
}

LoadFileExplorerImagePreviewRequest :: struct {
    file_path: string;
}

LoadFileExplorerImagePreviewResult :: struct {
    success: bool;
    width, height: s32;
    pixels: []u8;
}

AsyncTaskType :: enum u8 {
    SEARCH_TEXT;
    LOAD_FILE_EXPLORER_PREVIEW;
    LOAD_FILE_EXPLORER_IMAGE_PREVIEW;
}

AsyncTaskRequest :: struct {
    type: AsyncTaskType;
    using data: union {
        search_text: SearchTextRequest;
        load_file_explorer_preview: LoadFileExplorerPreviewRequest;
        load_file_explorer_image_preview: LoadFileExplorerImagePreviewRequest;
    }
}

AsyncTask :: struct {
    request: AsyncTaskRequest;
    result: union {
        load_file_explorer_preview: LoadFileExplorerPreviewResult;
        load_file_explorer_image_preview: LoadFileExplorerImagePreviewResult;
    }
}

Make_Unique_Thread_Work_Request :: (request: AsyncTaskRequest) -> bool {
    for next_tasks.* {
        if it.request.type == request.type {
            return false;
        }
    }
    array_add(next_tasks, .{request=request});
    return true;
}

Process_Async_Results :: () {
    while thread_worker_should_work {
        sleep_milliseconds(1);
    }

    for *task: working_tasks.* {
        if task.request.type == {
        case .LOAD_FILE_EXPLORER_PREVIEW;
            file_explorer_preview_available = true;
            free(task.request.load_file_explorer_preview.file_path);
        case .LOAD_FILE_EXPLORER_IMAGE_PREVIEW;
            file_explorer_image_preview_available = true;
            File_Explorer_Image_Preview_Clear();
            if task.result.load_file_explorer_image_preview.success {
                file_explorer_image_preview.file_path = task.request.load_file_explorer_image_preview.file_path;
                file_explorer_image_preview.width = task.result.load_file_explorer_image_preview.width;
                file_explorer_image_preview.height = task.result.load_file_explorer_image_preview.height;
                file_explorer_image_preview.pixels = task.result.load_file_explorer_image_preview.pixels;
                task.request.load_file_explorer_image_preview.file_path = .{};
                task.result.load_file_explorer_image_preview.pixels = .{};
            }
            free(task.request.load_file_explorer_image_preview.file_path);
        }
    }
    array_reset_keeping_memory(working_tasks);

    task_counts: [#run enum_highest_value(AsyncTaskType)+1]s32;
    for next_tasks.* {
        task_counts[cast(s32)(it.request.type)] += 1;
        if it.request.type == {
        case .LOAD_FILE_EXPLORER_PREVIEW;
            file_explorer_preview_available = false;
            Clear_Text_Buffer(*file_explorer_text_preview, true);
        case .LOAD_FILE_EXPLORER_IMAGE_PREVIEW;
            file_explorer_image_preview_available = false;
            File_Explorer_Image_Preview_Clear();
        }
    }
    // there's only one preview buffer; we can only take one request per frame
    assert(task_counts[AsyncTaskType.LOAD_FILE_EXPLORER_PREVIEW] <= 1);
    assert(task_counts[AsyncTaskType.LOAD_FILE_EXPLORER_IMAGE_PREVIEW] <= 1);

    next_tasks, working_tasks = working_tasks, next_tasks;
    thread_worker_should_work = working_tasks.count > 0;
}


main_thread_index: u32;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

thread_worker_should_run: bool;
thread_worker_should_work: bool;
thread_worker: Thread;

task_buffer_a: [..]AsyncTask;
task_buffer_b: [..]AsyncTask;

next_tasks: *[..]AsyncTask;
working_tasks: *[..]AsyncTask;
