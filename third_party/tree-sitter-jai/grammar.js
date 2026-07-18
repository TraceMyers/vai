// tree-sitter grammar for the Jai programming language.
//
// Scope note: in Vai, tree-sitter is responsible ONLY for syntax highlighting.
// Go-to-definition, find-references, and rename come from the Jai-compiler-backed
// semantic provider, not from this tree.  So this grammar is intentionally
// lexical/lenient first: it classifies tokens reliably over arbitrary real Jai
// source and never hard-fails, and can be enriched toward more structure later
// (e.g. distinguishing definitions from calls) without the highlighter breaking.

module.exports = grammar({
  name: 'jai',

  word: $ => $.identifier,

  extras: $ => [
    /\s+/,
    $.line_comment,
    $.block_comment,
  ],

  rules: {
    source_file: $ => repeat($._token),

    _token: $ => choice(
      $.keyword,
      $.directive,
      $.string,
      $.number,
      $.boolean,
      $.identifier,
      $.operator,
      $.punctuation,
    ),

    line_comment: _ => token(seq('//', /[^\n]*/)),

    // Non-nested block comments.  Real Jai allows nesting; that needs an
    // external scanner and is deferred past the highlighting spike.
    block_comment: _ => token(seq(
      '/*',
      /[^*]*\*+([^/*][^*]*\*+)*/,
      '/',
    )),

    string: _ => token(seq(
      '"',
      repeat(choice(/[^"\\\n]/, /\\./)),
      '"',
    )),

    number: _ => token(choice(
      /0[xX][0-9a-fA-F_]+/,
      /0[bB][01_]+/,
      /[0-9][0-9_]*\.[0-9_]+([eE][+-]?[0-9]+)?/,
      /[0-9][0-9_]*([eE][+-]?[0-9]+)?/,
    )),

    boolean: _ => token(choice('true', 'false', 'null')),

    directive: _ => token(seq('#', /[A-Za-z_][A-Za-z0-9_]*/)),

    keyword: _ => token(choice(
      'if', 'ifx', 'else', 'then', 'case',
      'while', 'for', 'break', 'continue', 'return', 'defer',
      'using', 'struct', 'enum', 'enum_flags', 'union',
      'cast', 'xx', 'inline', 'no_inline', 'remove',
      'size_of', 'type_info', 'type_of', 'operator',
      'push_context', 'context', 'it', 'it_index',
      'void', 'bool', 'string',
      's8', 's16', 's32', 's64', 'u8', 'u16', 'u32', 'u64',
      'int', 'float', 'float32', 'float64',
    )),

    identifier: _ => /[A-Za-z_][A-Za-z0-9_]*/,

    operator: _ => token(choice(
      '::', ':=', '->', '==', '!=', '<=', '>=', '&&', '||',
      '+=', '-=', '*=', '/=', '%=', '..', '---',
      '+', '-', '*', '/', '%', '=', '<', '>', '!', '&', '|', '^', '~',
    )),

    // Backtick is Jai's macro outer-scope reference operator (`ident inside
    // #expand macros); it must be a recognized token or parsing hard-fails.
    // Backtick is Jai's macro outer-scope reference operator (`ident inside
    // #expand macros); it must be a recognized token or parsing hard-fails.
    // NOTE: here-strings (#string TERM ... TERM) and nested block comments still
    // mis-tokenize their bodies as code; both need an external scanner.c, which
    // is deferred to the grammar-enrichment pass past the highlighting spike.
    punctuation: _ => token(choice('(', ')', '{', '}', '[', ']', ',', ';', ':', '.', '@', '$', '`', '?', '\\', '\'')),
  },
});
