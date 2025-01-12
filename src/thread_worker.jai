
ThreadWorker :: struct {
    thread: Thread;
}

MatchPatternResult :: struct {
    view_layer_id: u32;    
}

SearchTextTask :: struct {
    find_pattern: string;
}

AsyncTask :: union {
    search_text: SearchTextTask;    
}