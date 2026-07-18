
Thread_Worker :: struct  {

    Initialize :: () -> success: bool {
        next_tasks = *task_buffer_a;
        working_tasks = *task_buffer_b;
        atomic_swap(*thread_worker_should_run, 1);
        atomic_swap(*thread_worker_state, ThreadWorkerState.IDLE);
        thread_init(*thread_worker, Thread_Worker_Loop);
        thread_start(*thread_worker);
        return true;
    }

    Shutdown :: () {
        atomic_swap(*thread_worker_should_run, 0);
        while !thread_is_done(*thread_worker, 1) {;}
        thread_deinit(*thread_worker);

        for *task_buffer_a Discard_Async_Task(it);
        for *task_buffer_b Discard_Async_Task(it);
        next_tasks = null;
        working_tasks = null;
        array_reset(*task_buffer_a);
        array_reset(*task_buffer_b);
    }

}

Thread_Worker_Loop :: (t: *Thread) -> s64 {
    while atomic_read(*thread_worker_should_run) != 0 {
        if atomic_read(*thread_worker_state) == .WORKING {
            for working_tasks.* {
                Init_Task_Result(*it);
                if it.request.type == {
                case .LOAD_FILE_EXPLORER_PREVIEW;
                    Load_File_Explorer_Preview(*it);
                case .LOAD_FILE_EXPLORER_IMAGE_PREVIEW;
                    Load_File_Explorer_Image_Preview(*it);
                case .LOAD_FILE_EXPLORER_SCENE_PREVIEW;
                    Load_File_Explorer_Scene_Preview(*it);
                }
                reset_temporary_storage();
            }
            atomic_swap(*thread_worker_state, ThreadWorkerState.RESULTS_READY);
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
    case .LOAD_FILE_EXPLORER_SCENE_PREVIEW;
        task.result.load_file_explorer_scene_preview = .{};
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
        Image_Preview_Load_File(file_path, *task.result.load_file_explorer_image_preview);
        Prepare_File_Explorer_Image_Preview_GPU_Result(task);
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
    Prepare_File_Explorer_Image_Preview_GPU_Result(task);
}

Prepare_File_Explorer_Image_Preview_GPU_Result :: (task: *AsyncTask) {
    result := *task.result.load_file_explorer_image_preview;
    if !result.success {
        return;
    }
    generation := task.request.load_file_explorer_image_preview.generation;
    if generation != 0 && atomic_read(*file_explorer_preview_generation) != generation {
        return;
    }
    if !File_Explorer_Image_Preview_Upload_Result_To_GPU(result) {
        result.success = false;
    }
}

Load_File_Explorer_Scene_Preview :: (task: *AsyncTask) {
    Scene_Preview_Load_File(task.request.load_file_explorer_scene_preview.file_path, *task.result.load_file_explorer_scene_preview);
    result := *task.result.load_file_explorer_scene_preview;
    if !result.success {
        return;
    }

    generation := task.request.load_file_explorer_scene_preview.generation;
    if generation != 0 && atomic_read(*file_explorer_preview_generation) != generation {
        return;
    }
    if !Scene_Preview_Upload_Result_To_GPU(result) {
        Scene_Preview_Free_Result_Geometry(result);
        String_Reset(*result.error_message);
        result.error_message = copy_string("The scene could not be prepared for preview.");
        result.success = false;
    }
}

SearchTextRequest :: struct {
    find_pattern: string;
}

LoadFileExplorerPreviewRequest :: struct {
    file_path: string;
    generation: u64;
}

LoadFileExplorerPreviewResult :: struct {
    success: bool;
}

LoadFileExplorerImagePreviewRequest :: struct {
    file_path: string;
    generation: u64;
}

LoadFileExplorerImagePreviewResult :: struct {
    success: bool;
    width, height: s32;
    pixels: []u8;
    texture: u32;
}

LoadFileExplorerScenePreviewRequest :: struct {
    file_path: string;
    generation: u64;
}

LoadFileExplorerScenePreviewResult :: struct {
    success: bool;
    vertices: []FileExplorerSceneVertex;
    vertex_buffer: u32;
    materials: []FileExplorerSceneMaterial;
    draw_ranges: []FileExplorerSceneDrawRange;
    bounds_min: Vector3;
    bounds_max: Vector3;
    error_message: string;
}

AsyncTaskType :: enum u8 {
    SEARCH_TEXT;
    LOAD_FILE_EXPLORER_PREVIEW;
    LOAD_FILE_EXPLORER_IMAGE_PREVIEW;
    LOAD_FILE_EXPLORER_SCENE_PREVIEW;
}

AsyncTaskRequest :: struct {
    type: AsyncTaskType;
    using data: union {
        search_text: SearchTextRequest;
        load_file_explorer_preview: LoadFileExplorerPreviewRequest;
        load_file_explorer_image_preview: LoadFileExplorerImagePreviewRequest;
        load_file_explorer_scene_preview: LoadFileExplorerScenePreviewRequest;
    }
}

AsyncTask :: struct {
    request: AsyncTaskRequest;
    result: union {
        load_file_explorer_preview: LoadFileExplorerPreviewResult;
        load_file_explorer_image_preview: LoadFileExplorerImagePreviewResult;
        load_file_explorer_scene_preview: LoadFileExplorerScenePreviewResult;
    }
}

Make_Unique_Thread_Work_Request :: (request: AsyncTaskRequest) -> bool {
    for *task: next_tasks.* {
        if task.request.type == request.type {
            Discard_Async_Task(task);
            task.* = .{request=request};
            return true;
        }
    }
    array_add(next_tasks, .{request=request});
    return true;
}

Async_Task_Is_File_Explorer_Preview :: (task_type: AsyncTaskType) -> bool {
    return task_type == .LOAD_FILE_EXPLORER_PREVIEW
        || task_type == .LOAD_FILE_EXPLORER_IMAGE_PREVIEW
        || task_type == .LOAD_FILE_EXPLORER_SCENE_PREVIEW;
}

Discard_Async_Task :: (task: *AsyncTask) {
    if task.request.type == {
    case .SEARCH_TEXT;
    case .LOAD_FILE_EXPLORER_PREVIEW;
        free(task.request.load_file_explorer_preview.file_path);
        task.request.load_file_explorer_preview.file_path = .{};
    case .LOAD_FILE_EXPLORER_IMAGE_PREVIEW;
        if task.result.load_file_explorer_image_preview.texture != 0 {
            glDeleteTextures(1, *task.result.load_file_explorer_image_preview.texture);
            task.result.load_file_explorer_image_preview.texture = 0;
        }
        if task.result.load_file_explorer_image_preview.pixels.data != null {
            free(task.result.load_file_explorer_image_preview.pixels.data);
            task.result.load_file_explorer_image_preview.pixels = .{};
        }
        free(task.request.load_file_explorer_image_preview.file_path);
        task.request.load_file_explorer_image_preview.file_path = .{};
    case .LOAD_FILE_EXPLORER_SCENE_PREVIEW;
        Scene_Preview_Free_Result_Geometry(*task.result.load_file_explorer_scene_preview);
        String_Reset(*task.result.load_file_explorer_scene_preview.error_message);
        free(task.request.load_file_explorer_scene_preview.file_path);
        task.request.load_file_explorer_scene_preview.file_path = .{};
    }
}

Cancel_Pending_File_Explorer_Preview_Tasks :: () {
    if next_tasks == null then return;
    index := next_tasks.count - 1;
    while index >= 0 {
        if Async_Task_Is_File_Explorer_Preview(next_tasks.*[index].request.type) {
            Discard_Async_Task(*next_tasks.*[index]);
            array_unordered_remove_by_index(next_tasks, index);
        }
        index -= 1;
    }
}

Process_Async_Results :: () -> ui_changed: bool {
    ui_changed := false;
    if next_tasks == null || working_tasks == null {
        return false;
    }
    if atomic_read(*thread_worker_state) == .WORKING {
        return false;
    }

    for *task: working_tasks.* {
        if task.request.type == {
        case .LOAD_FILE_EXPLORER_PREVIEW;
            ui_changed = true;
            file_explorer_preview_available = true;
            request := *task.request.load_file_explorer_preview;
            if request.generation == 0 || File_Explorer_Preview_Request_Is_Current(.TEXT, request.file_path, request.generation) {
                file_explorer_preview_state = ifx task.result.load_file_explorer_preview.success then .READY else .UNAVAILABLE;
            }
        case .LOAD_FILE_EXPLORER_IMAGE_PREVIEW;
            ui_changed = true;
            file_explorer_image_preview_available = true;
            request := *task.request.load_file_explorer_image_preview;
            current := request.generation == 0 || File_Explorer_Preview_Request_Is_Current(.IMAGE, request.file_path, request.generation);
            if current {
                File_Explorer_Image_Preview_Clear();
                if task.result.load_file_explorer_image_preview.success {
                    file_explorer_image_preview.file_path = request.file_path;
                    file_explorer_image_preview.width = task.result.load_file_explorer_image_preview.width;
                    file_explorer_image_preview.height = task.result.load_file_explorer_image_preview.height;
                    file_explorer_image_preview.pixels = task.result.load_file_explorer_image_preview.pixels;
                    file_explorer_image_preview.texture = task.result.load_file_explorer_image_preview.texture;
                    task.request.load_file_explorer_image_preview.file_path = .{};
                    task.result.load_file_explorer_image_preview.pixels = .{};
                    task.result.load_file_explorer_image_preview.texture = 0;
                    file_explorer_preview_state = .READY;
                } else {
                    file_explorer_preview_state = .UNAVAILABLE;
                }
            }
        case .LOAD_FILE_EXPLORER_SCENE_PREVIEW;
            ui_changed = true;
            file_explorer_scene_preview_available = true;
            request := *task.request.load_file_explorer_scene_preview;
            current := request.generation == 0 || File_Explorer_Preview_Request_Is_Current(.SCENE, request.file_path, request.generation);
            if current {
                File_Explorer_Scene_Preview_Clear();
                file_explorer_scene_preview.file_path = request.file_path;
                file_explorer_scene_preview.vertices = task.result.load_file_explorer_scene_preview.vertices;
                file_explorer_scene_preview.vertex_buffer = task.result.load_file_explorer_scene_preview.vertex_buffer;
                file_explorer_scene_preview.materials = task.result.load_file_explorer_scene_preview.materials;
                file_explorer_scene_preview.draw_ranges = task.result.load_file_explorer_scene_preview.draw_ranges;
                file_explorer_scene_preview.bounds_min = task.result.load_file_explorer_scene_preview.bounds_min;
                file_explorer_scene_preview.bounds_max = task.result.load_file_explorer_scene_preview.bounds_max;
                file_explorer_scene_preview.error_message = task.result.load_file_explorer_scene_preview.error_message;
                task.request.load_file_explorer_scene_preview.file_path = .{};
                task.result.load_file_explorer_scene_preview.vertices = .{};
                task.result.load_file_explorer_scene_preview.vertex_buffer = 0;
                task.result.load_file_explorer_scene_preview.materials = .{};
                task.result.load_file_explorer_scene_preview.draw_ranges = .{};
                task.result.load_file_explorer_scene_preview.error_message = .{};
                file_explorer_preview_state = ifx task.result.load_file_explorer_scene_preview.success then .READY else .UNAVAILABLE;
            }
        }
        Discard_Async_Task(task);
    }
    array_reset_keeping_memory(working_tasks);
    atomic_swap(*thread_worker_state, ThreadWorkerState.IDLE);

    task_counts: [#run enum_highest_value(AsyncTaskType)+1]s32;
    for next_tasks.* {
        task_counts[cast(s32)(it.request.type)] += 1;
        if it.request.type == {
        case .LOAD_FILE_EXPLORER_PREVIEW;
            ui_changed = true;
            file_explorer_preview_available = false;
            Clear_Text_Buffer(*file_explorer_text_preview, true);
        case .LOAD_FILE_EXPLORER_IMAGE_PREVIEW;
            ui_changed = true;
            file_explorer_image_preview_available = false;
            File_Explorer_Image_Preview_Clear();
        case .LOAD_FILE_EXPLORER_SCENE_PREVIEW;
            ui_changed = true;
            file_explorer_scene_preview_available = false;
            File_Explorer_Scene_Preview_Clear();
        }
    }
    // there's only one preview buffer; we can only take one request per frame
    assert(task_counts[AsyncTaskType.LOAD_FILE_EXPLORER_PREVIEW] <= 1);
    assert(task_counts[AsyncTaskType.LOAD_FILE_EXPLORER_IMAGE_PREVIEW] <= 1);
    assert(task_counts[AsyncTaskType.LOAD_FILE_EXPLORER_SCENE_PREVIEW] <= 1);

    if next_tasks.count > 0 {
        next_tasks, working_tasks = working_tasks, next_tasks;
        atomic_swap(*thread_worker_state, ThreadWorkerState.WORKING);
    }
    return ui_changed;
}

Crash_Test_Completed_Scene_Task_Invalidates_UI_Impl :: () -> bool {
    array_reset_keeping_memory(*task_buffer_a);
    array_reset_keeping_memory(*task_buffer_b);
    next_tasks = *task_buffer_a;
    working_tasks = *task_buffer_b;
    thread_worker_state = .IDLE;

    task: AsyncTask;
    task.request.type = .LOAD_FILE_EXPLORER_SCENE_PREVIEW;
    task.request.load_file_explorer_scene_preview.file_path = copy_string("__scene_preview_invalidation_test__");
    task.result.load_file_explorer_scene_preview.error_message = copy_string("__expected_preview_error__");
    array_add(working_tasks, task);

    ui_changed := Process_Async_Results();
    result_installed := file_explorer_scene_preview.file_path == "__scene_preview_invalidation_test__"
        && file_explorer_scene_preview.error_message == "__expected_preview_error__";

    File_Explorer_Scene_Preview_Clear();
    array_reset_keeping_memory(*task_buffer_a);
    array_reset_keeping_memory(*task_buffer_b);
    next_tasks = null;
    working_tasks = null;
    return ui_changed && result_installed;
}

Crash_Test_Async_Result_Poll_Is_Non_Blocking_Impl :: () -> bool {
    array_reset_keeping_memory(*task_buffer_a);
    array_reset_keeping_memory(*task_buffer_b);
    next_tasks = *task_buffer_a;
    working_tasks = *task_buffer_b;
    thread_worker_state = .WORKING;

    ui_changed := Process_Async_Results();

    thread_worker_state = .IDLE;
    next_tasks = null;
    working_tasks = null;
    return !ui_changed;
}

Crash_Test_Latest_Preview_Request_Wins_Impl :: () -> bool {
    array_reset_keeping_memory(*task_buffer_a);
    array_reset_keeping_memory(*task_buffer_b);
    next_tasks = *task_buffer_a;
    working_tasks = *task_buffer_b;
    thread_worker_state = .WORKING;

    first := AsyncTaskRequest.{
        type=.LOAD_FILE_EXPLORER_SCENE_PREVIEW,
        load_file_explorer_scene_preview=.{file_path=copy_string("__stale_scene__"), generation=1},
    };
    Make_Unique_Thread_Work_Request(first);
    Cancel_Pending_File_Explorer_Preview_Tasks();
    latest := AsyncTaskRequest.{
        type=.LOAD_FILE_EXPLORER_IMAGE_PREVIEW,
        load_file_explorer_image_preview=.{file_path=copy_string("__latest_image__"), generation=2},
    };
    Make_Unique_Thread_Work_Request(latest);

    passed := next_tasks.count == 1
        && next_tasks.*[0].request.type == .LOAD_FILE_EXPLORER_IMAGE_PREVIEW
        && next_tasks.*[0].request.load_file_explorer_image_preview.file_path == "__latest_image__";
    if next_tasks.count > 0 {
        Discard_Async_Task(*next_tasks.*[0]);
    }
    array_reset_keeping_memory(next_tasks);
    thread_worker_state = .IDLE;
    next_tasks = null;
    working_tasks = null;
    return passed;
}


main_thread_index: u32;

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

ThreadWorkerState :: enum s32 {
    IDLE;
    WORKING;
    RESULTS_READY;
}

thread_worker_should_run: s32;
thread_worker_state: ThreadWorkerState;
thread_worker: Thread;

task_buffer_a: [..]AsyncTask;
task_buffer_b: [..]AsyncTask;

next_tasks: *[..]AsyncTask;
working_tasks: *[..]AsyncTask;
