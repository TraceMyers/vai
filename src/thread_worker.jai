
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
    }
}

Load_File_Explorer_Preview :: (task: *AsyncTask) {
    file_path := task.request.load_file_explorer_preview.file_path;
    task.result.load_file_explorer_preview.success = Load_File_Into_Buffer(file_path, *file_explorer_text_preview, false);
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

AsyncTaskType :: enum u8 {
    SEARCH_TEXT;
    LOAD_FILE_EXPLORER_PREVIEW;
}

AsyncTaskRequest :: struct {
    type: AsyncTaskType;
    using data: union {
        search_text: SearchTextRequest;
        load_file_explorer_preview: LoadFileExplorerPreviewRequest;
    }
}

AsyncTask :: struct {
    request: AsyncTaskRequest;
    result: union {
        load_file_explorer_preview: LoadFileExplorerPreviewResult;
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

    for working_tasks.* {
        if it.request.type == {
        case .LOAD_FILE_EXPLORER_PREVIEW;
            file_explorer_preview_available = true;
            free(it.request.load_file_explorer_preview.file_path);
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
        }
    }
    // there's only one preview buffer; we can only take one request per frame
    assert(task_counts[AsyncTaskType.LOAD_FILE_EXPLORER_PREVIEW] <= 1);

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
