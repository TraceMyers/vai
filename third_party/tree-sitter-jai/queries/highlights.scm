; Highlight captures for Jai. Capture names map to Vai theme color indices in
; the host (see the capture->color table in src). Keep names conventional
; (tree-sitter highlight naming) so other tooling can reuse this file.

(line_comment)  @comment
(block_comment) @comment

(string)  @string
(number)  @number
(boolean) @constant.builtin

(keyword)   @keyword
(directive) @keyword.directive

(operator)    @operator
(punctuation) @punctuation.delimiter

(identifier) @variable
