#include "tree_sitter/parser.h"

#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#endif

#define LANGUAGE_VERSION 14
#define STATE_COUNT 5
#define LARGE_STATE_COUNT 4
#define SYMBOL_COUNT 14
#define ALIAS_COUNT 0
#define TOKEN_COUNT 11
#define EXTERNAL_TOKEN_COUNT 0
#define FIELD_COUNT 0
#define MAX_ALIAS_SEQUENCE_LENGTH 2
#define PRODUCTION_ID_COUNT 1

enum ts_symbol_identifiers {
  sym_identifier = 1,
  sym_line_comment = 2,
  sym_block_comment = 3,
  sym_string = 4,
  sym_number = 5,
  sym_boolean = 6,
  sym_directive = 7,
  sym_keyword = 8,
  sym_operator = 9,
  sym_punctuation = 10,
  sym_source_file = 11,
  sym__token = 12,
  aux_sym_source_file_repeat1 = 13,
};

static const char * const ts_symbol_names[] = {
  [ts_builtin_sym_end] = "end",
  [sym_identifier] = "identifier",
  [sym_line_comment] = "line_comment",
  [sym_block_comment] = "block_comment",
  [sym_string] = "string",
  [sym_number] = "number",
  [sym_boolean] = "boolean",
  [sym_directive] = "directive",
  [sym_keyword] = "keyword",
  [sym_operator] = "operator",
  [sym_punctuation] = "punctuation",
  [sym_source_file] = "source_file",
  [sym__token] = "_token",
  [aux_sym_source_file_repeat1] = "source_file_repeat1",
};

static const TSSymbol ts_symbol_map[] = {
  [ts_builtin_sym_end] = ts_builtin_sym_end,
  [sym_identifier] = sym_identifier,
  [sym_line_comment] = sym_line_comment,
  [sym_block_comment] = sym_block_comment,
  [sym_string] = sym_string,
  [sym_number] = sym_number,
  [sym_boolean] = sym_boolean,
  [sym_directive] = sym_directive,
  [sym_keyword] = sym_keyword,
  [sym_operator] = sym_operator,
  [sym_punctuation] = sym_punctuation,
  [sym_source_file] = sym_source_file,
  [sym__token] = sym__token,
  [aux_sym_source_file_repeat1] = aux_sym_source_file_repeat1,
};

static const TSSymbolMetadata ts_symbol_metadata[] = {
  [ts_builtin_sym_end] = {
    .visible = false,
    .named = true,
  },
  [sym_identifier] = {
    .visible = true,
    .named = true,
  },
  [sym_line_comment] = {
    .visible = true,
    .named = true,
  },
  [sym_block_comment] = {
    .visible = true,
    .named = true,
  },
  [sym_string] = {
    .visible = true,
    .named = true,
  },
  [sym_number] = {
    .visible = true,
    .named = true,
  },
  [sym_boolean] = {
    .visible = true,
    .named = true,
  },
  [sym_directive] = {
    .visible = true,
    .named = true,
  },
  [sym_keyword] = {
    .visible = true,
    .named = true,
  },
  [sym_operator] = {
    .visible = true,
    .named = true,
  },
  [sym_punctuation] = {
    .visible = true,
    .named = true,
  },
  [sym_source_file] = {
    .visible = true,
    .named = true,
  },
  [sym__token] = {
    .visible = false,
    .named = true,
  },
  [aux_sym_source_file_repeat1] = {
    .visible = false,
    .named = false,
  },
};

static const TSSymbol ts_alias_sequences[PRODUCTION_ID_COUNT][MAX_ALIAS_SEQUENCE_LENGTH] = {
  [0] = {0},
};

static const uint16_t ts_non_terminal_alias_map[] = {
  0,
};

static const TSStateId ts_primary_state_ids[STATE_COUNT] = {
  [0] = 0,
  [1] = 1,
  [2] = 2,
  [3] = 3,
  [4] = 4,
};

static bool ts_lex(TSLexer *lexer, TSStateId state) {
  START_LEXER();
  eof = lexer->eof(lexer);
  switch (state) {
    case 0:
      if (eof) ADVANCE(12);
      ADVANCE_MAP(
        '!', 28,
        '"', 1,
        '#', 10,
        '%', 28,
        '&', 25,
        '*', 28,
        '+', 28,
        '-', 27,
        '.', 31,
        '/', 26,
        '0', 16,
        ':', 32,
        '<', 28,
        '=', 28,
        '>', 28,
        '|', 29,
        '^', 24,
        '~', 24,
      );
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') SKIP(0);
      if (('1' <= lookahead && lookahead <= '9')) ADVANCE(17);
      if (('$' <= lookahead && lookahead <= '@') ||
          ('[' <= lookahead && lookahead <= ']') ||
          lookahead == '`' ||
          ('{' <= lookahead && lookahead <= '}')) ADVANCE(30);
      if (('A' <= lookahead && lookahead <= 'z')) ADVANCE(23);
      END_STATE();
    case 1:
      if (lookahead == '"') ADVANCE(15);
      if (lookahead == '\\') ADVANCE(11);
      if (lookahead != 0 &&
          lookahead != '\n') ADVANCE(1);
      END_STATE();
    case 2:
      if (lookahead == '*') ADVANCE(2);
      if (lookahead == '/') ADVANCE(14);
      if (lookahead != 0) ADVANCE(3);
      END_STATE();
    case 3:
      if (lookahead == '*') ADVANCE(2);
      if (lookahead != 0) ADVANCE(3);
      END_STATE();
    case 4:
      if (lookahead == '-') ADVANCE(24);
      END_STATE();
    case 5:
      if (lookahead == '+' ||
          lookahead == '-') ADVANCE(7);
      if (('0' <= lookahead && lookahead <= '9')) ADVANCE(20);
      END_STATE();
    case 6:
      if (lookahead == '0' ||
          lookahead == '1' ||
          lookahead == '_') ADVANCE(19);
      END_STATE();
    case 7:
      if (('0' <= lookahead && lookahead <= '9')) ADVANCE(20);
      END_STATE();
    case 8:
      if (('0' <= lookahead && lookahead <= '9') ||
          lookahead == '_') ADVANCE(18);
      END_STATE();
    case 9:
      if (('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'F') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'f')) ADVANCE(21);
      END_STATE();
    case 10:
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(22);
      END_STATE();
    case 11:
      if (lookahead != 0 &&
          lookahead != '\n') ADVANCE(1);
      END_STATE();
    case 12:
      ACCEPT_TOKEN(ts_builtin_sym_end);
      END_STATE();
    case 13:
      ACCEPT_TOKEN(sym_line_comment);
      if (lookahead != 0 &&
          lookahead != '\n') ADVANCE(13);
      END_STATE();
    case 14:
      ACCEPT_TOKEN(sym_block_comment);
      END_STATE();
    case 15:
      ACCEPT_TOKEN(sym_string);
      END_STATE();
    case 16:
      ACCEPT_TOKEN(sym_number);
      if (lookahead == '.') ADVANCE(8);
      if (lookahead == 'B' ||
          lookahead == 'b') ADVANCE(6);
      if (lookahead == 'E' ||
          lookahead == 'e') ADVANCE(5);
      if (lookahead == 'X' ||
          lookahead == 'x') ADVANCE(9);
      if (('0' <= lookahead && lookahead <= '9') ||
          lookahead == '_') ADVANCE(17);
      END_STATE();
    case 17:
      ACCEPT_TOKEN(sym_number);
      if (lookahead == '.') ADVANCE(8);
      if (lookahead == 'E' ||
          lookahead == 'e') ADVANCE(5);
      if (('0' <= lookahead && lookahead <= '9') ||
          lookahead == '_') ADVANCE(17);
      END_STATE();
    case 18:
      ACCEPT_TOKEN(sym_number);
      if (lookahead == 'E' ||
          lookahead == 'e') ADVANCE(5);
      if (('0' <= lookahead && lookahead <= '9') ||
          lookahead == '_') ADVANCE(18);
      END_STATE();
    case 19:
      ACCEPT_TOKEN(sym_number);
      if (lookahead == '0' ||
          lookahead == '1' ||
          lookahead == '_') ADVANCE(19);
      END_STATE();
    case 20:
      ACCEPT_TOKEN(sym_number);
      if (('0' <= lookahead && lookahead <= '9')) ADVANCE(20);
      END_STATE();
    case 21:
      ACCEPT_TOKEN(sym_number);
      if (('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'F') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'f')) ADVANCE(21);
      END_STATE();
    case 22:
      ACCEPT_TOKEN(sym_directive);
      if (('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(22);
      END_STATE();
    case 23:
      ACCEPT_TOKEN(sym_identifier);
      if (('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(23);
      END_STATE();
    case 24:
      ACCEPT_TOKEN(sym_operator);
      END_STATE();
    case 25:
      ACCEPT_TOKEN(sym_operator);
      if (lookahead == '&') ADVANCE(24);
      END_STATE();
    case 26:
      ACCEPT_TOKEN(sym_operator);
      if (lookahead == '*') ADVANCE(3);
      if (lookahead == '/') ADVANCE(13);
      if (lookahead == '=') ADVANCE(24);
      END_STATE();
    case 27:
      ACCEPT_TOKEN(sym_operator);
      if (lookahead == '-') ADVANCE(4);
      if (lookahead == '=' ||
          lookahead == '>') ADVANCE(24);
      END_STATE();
    case 28:
      ACCEPT_TOKEN(sym_operator);
      if (lookahead == '=') ADVANCE(24);
      END_STATE();
    case 29:
      ACCEPT_TOKEN(sym_operator);
      if (lookahead == '|') ADVANCE(24);
      END_STATE();
    case 30:
      ACCEPT_TOKEN(sym_punctuation);
      END_STATE();
    case 31:
      ACCEPT_TOKEN(sym_punctuation);
      if (lookahead == '.') ADVANCE(24);
      END_STATE();
    case 32:
      ACCEPT_TOKEN(sym_punctuation);
      if (lookahead == ':' ||
          lookahead == '=') ADVANCE(24);
      END_STATE();
    default:
      return false;
  }
}

static bool ts_lex_keywords(TSLexer *lexer, TSStateId state) {
  START_LEXER();
  eof = lexer->eof(lexer);
  switch (state) {
    case 0:
      ADVANCE_MAP(
        'b', 1,
        'c', 2,
        'd', 3,
        'e', 4,
        'f', 5,
        'i', 6,
        'n', 7,
        'o', 8,
        'p', 9,
        'r', 10,
        's', 11,
        't', 12,
        'u', 13,
        'v', 14,
        'w', 15,
        'x', 16,
      );
      if (('\t' <= lookahead && lookahead <= '\r') ||
          lookahead == ' ') SKIP(0);
      END_STATE();
    case 1:
      if (lookahead == 'o') ADVANCE(17);
      if (lookahead == 'r') ADVANCE(18);
      END_STATE();
    case 2:
      if (lookahead == 'a') ADVANCE(19);
      if (lookahead == 'o') ADVANCE(20);
      END_STATE();
    case 3:
      if (lookahead == 'e') ADVANCE(21);
      END_STATE();
    case 4:
      if (lookahead == 'l') ADVANCE(22);
      if (lookahead == 'n') ADVANCE(23);
      END_STATE();
    case 5:
      if (lookahead == 'a') ADVANCE(24);
      if (lookahead == 'l') ADVANCE(25);
      if (lookahead == 'o') ADVANCE(26);
      END_STATE();
    case 6:
      if (lookahead == 'f') ADVANCE(27);
      if (lookahead == 'n') ADVANCE(28);
      if (lookahead == 't') ADVANCE(29);
      END_STATE();
    case 7:
      if (lookahead == 'o') ADVANCE(30);
      if (lookahead == 'u') ADVANCE(31);
      END_STATE();
    case 8:
      if (lookahead == 'p') ADVANCE(32);
      END_STATE();
    case 9:
      if (lookahead == 'u') ADVANCE(33);
      END_STATE();
    case 10:
      if (lookahead == 'e') ADVANCE(34);
      END_STATE();
    case 11:
      if (lookahead == '1') ADVANCE(35);
      if (lookahead == '3') ADVANCE(36);
      if (lookahead == '6') ADVANCE(37);
      if (lookahead == '8') ADVANCE(38);
      if (lookahead == 'i') ADVANCE(39);
      if (lookahead == 't') ADVANCE(40);
      END_STATE();
    case 12:
      if (lookahead == 'h') ADVANCE(41);
      if (lookahead == 'r') ADVANCE(42);
      if (lookahead == 'y') ADVANCE(43);
      END_STATE();
    case 13:
      if (lookahead == '1') ADVANCE(44);
      if (lookahead == '3') ADVANCE(45);
      if (lookahead == '6') ADVANCE(46);
      if (lookahead == '8') ADVANCE(38);
      if (lookahead == 'n') ADVANCE(47);
      if (lookahead == 's') ADVANCE(48);
      END_STATE();
    case 14:
      if (lookahead == 'o') ADVANCE(49);
      END_STATE();
    case 15:
      if (lookahead == 'h') ADVANCE(50);
      END_STATE();
    case 16:
      if (lookahead == 'x') ADVANCE(38);
      END_STATE();
    case 17:
      if (lookahead == 'o') ADVANCE(51);
      END_STATE();
    case 18:
      if (lookahead == 'e') ADVANCE(52);
      END_STATE();
    case 19:
      if (lookahead == 's') ADVANCE(53);
      END_STATE();
    case 20:
      if (lookahead == 'n') ADVANCE(54);
      END_STATE();
    case 21:
      if (lookahead == 'f') ADVANCE(55);
      END_STATE();
    case 22:
      if (lookahead == 's') ADVANCE(56);
      END_STATE();
    case 23:
      if (lookahead == 'u') ADVANCE(57);
      END_STATE();
    case 24:
      if (lookahead == 'l') ADVANCE(58);
      END_STATE();
    case 25:
      if (lookahead == 'o') ADVANCE(59);
      END_STATE();
    case 26:
      if (lookahead == 'r') ADVANCE(38);
      END_STATE();
    case 27:
      ACCEPT_TOKEN(sym_keyword);
      if (lookahead == 'x') ADVANCE(38);
      END_STATE();
    case 28:
      if (lookahead == 'l') ADVANCE(60);
      if (lookahead == 't') ADVANCE(38);
      END_STATE();
    case 29:
      ACCEPT_TOKEN(sym_keyword);
      if (lookahead == '_') ADVANCE(61);
      END_STATE();
    case 30:
      if (lookahead == '_') ADVANCE(62);
      END_STATE();
    case 31:
      if (lookahead == 'l') ADVANCE(63);
      END_STATE();
    case 32:
      if (lookahead == 'e') ADVANCE(64);
      END_STATE();
    case 33:
      if (lookahead == 's') ADVANCE(65);
      END_STATE();
    case 34:
      if (lookahead == 'm') ADVANCE(66);
      if (lookahead == 't') ADVANCE(67);
      END_STATE();
    case 35:
      if (lookahead == '6') ADVANCE(38);
      END_STATE();
    case 36:
      if (lookahead == '2') ADVANCE(38);
      END_STATE();
    case 37:
      if (lookahead == '4') ADVANCE(38);
      END_STATE();
    case 38:
      ACCEPT_TOKEN(sym_keyword);
      END_STATE();
    case 39:
      if (lookahead == 'z') ADVANCE(68);
      END_STATE();
    case 40:
      if (lookahead == 'r') ADVANCE(69);
      END_STATE();
    case 41:
      if (lookahead == 'e') ADVANCE(70);
      END_STATE();
    case 42:
      if (lookahead == 'u') ADVANCE(71);
      END_STATE();
    case 43:
      if (lookahead == 'p') ADVANCE(72);
      END_STATE();
    case 44:
      if (lookahead == '6') ADVANCE(38);
      END_STATE();
    case 45:
      if (lookahead == '2') ADVANCE(38);
      END_STATE();
    case 46:
      if (lookahead == '4') ADVANCE(38);
      END_STATE();
    case 47:
      if (lookahead == 'i') ADVANCE(73);
      END_STATE();
    case 48:
      if (lookahead == 'i') ADVANCE(74);
      END_STATE();
    case 49:
      if (lookahead == 'i') ADVANCE(75);
      END_STATE();
    case 50:
      if (lookahead == 'i') ADVANCE(76);
      END_STATE();
    case 51:
      if (lookahead == 'l') ADVANCE(38);
      END_STATE();
    case 52:
      if (lookahead == 'a') ADVANCE(77);
      END_STATE();
    case 53:
      if (lookahead == 'e' ||
          lookahead == 't') ADVANCE(38);
      END_STATE();
    case 54:
      if (lookahead == 't') ADVANCE(78);
      END_STATE();
    case 55:
      if (lookahead == 'e') ADVANCE(79);
      END_STATE();
    case 56:
      if (lookahead == 'e') ADVANCE(38);
      END_STATE();
    case 57:
      if (lookahead == 'm') ADVANCE(80);
      END_STATE();
    case 58:
      if (lookahead == 's') ADVANCE(81);
      END_STATE();
    case 59:
      if (lookahead == 'a') ADVANCE(82);
      END_STATE();
    case 60:
      if (lookahead == 'i') ADVANCE(83);
      END_STATE();
    case 61:
      if (lookahead == 'i') ADVANCE(84);
      END_STATE();
    case 62:
      if (lookahead == 'i') ADVANCE(85);
      END_STATE();
    case 63:
      if (lookahead == 'l') ADVANCE(86);
      END_STATE();
    case 64:
      if (lookahead == 'r') ADVANCE(87);
      END_STATE();
    case 65:
      if (lookahead == 'h') ADVANCE(88);
      END_STATE();
    case 66:
      if (lookahead == 'o') ADVANCE(89);
      END_STATE();
    case 67:
      if (lookahead == 'u') ADVANCE(90);
      END_STATE();
    case 68:
      if (lookahead == 'e') ADVANCE(91);
      END_STATE();
    case 69:
      if (lookahead == 'i') ADVANCE(92);
      if (lookahead == 'u') ADVANCE(93);
      END_STATE();
    case 70:
      if (lookahead == 'n') ADVANCE(38);
      END_STATE();
    case 71:
      if (lookahead == 'e') ADVANCE(86);
      END_STATE();
    case 72:
      if (lookahead == 'e') ADVANCE(94);
      END_STATE();
    case 73:
      if (lookahead == 'o') ADVANCE(95);
      END_STATE();
    case 74:
      if (lookahead == 'n') ADVANCE(96);
      END_STATE();
    case 75:
      if (lookahead == 'd') ADVANCE(38);
      END_STATE();
    case 76:
      if (lookahead == 'l') ADVANCE(97);
      END_STATE();
    case 77:
      if (lookahead == 'k') ADVANCE(38);
      END_STATE();
    case 78:
      if (lookahead == 'e') ADVANCE(98);
      if (lookahead == 'i') ADVANCE(99);
      END_STATE();
    case 79:
      if (lookahead == 'r') ADVANCE(38);
      END_STATE();
    case 80:
      ACCEPT_TOKEN(sym_keyword);
      if (lookahead == '_') ADVANCE(100);
      END_STATE();
    case 81:
      if (lookahead == 'e') ADVANCE(86);
      END_STATE();
    case 82:
      if (lookahead == 't') ADVANCE(101);
      END_STATE();
    case 83:
      if (lookahead == 'n') ADVANCE(102);
      END_STATE();
    case 84:
      if (lookahead == 'n') ADVANCE(103);
      END_STATE();
    case 85:
      if (lookahead == 'n') ADVANCE(104);
      END_STATE();
    case 86:
      ACCEPT_TOKEN(sym_boolean);
      END_STATE();
    case 87:
      if (lookahead == 'a') ADVANCE(105);
      END_STATE();
    case 88:
      if (lookahead == '_') ADVANCE(106);
      END_STATE();
    case 89:
      if (lookahead == 'v') ADVANCE(107);
      END_STATE();
    case 90:
      if (lookahead == 'r') ADVANCE(108);
      END_STATE();
    case 91:
      if (lookahead == '_') ADVANCE(109);
      END_STATE();
    case 92:
      if (lookahead == 'n') ADVANCE(110);
      END_STATE();
    case 93:
      if (lookahead == 'c') ADVANCE(111);
      END_STATE();
    case 94:
      if (lookahead == '_') ADVANCE(112);
      END_STATE();
    case 95:
      if (lookahead == 'n') ADVANCE(38);
      END_STATE();
    case 96:
      if (lookahead == 'g') ADVANCE(38);
      END_STATE();
    case 97:
      if (lookahead == 'e') ADVANCE(38);
      END_STATE();
    case 98:
      if (lookahead == 'x') ADVANCE(113);
      END_STATE();
    case 99:
      if (lookahead == 'n') ADVANCE(114);
      END_STATE();
    case 100:
      if (lookahead == 'f') ADVANCE(115);
      END_STATE();
    case 101:
      ACCEPT_TOKEN(sym_keyword);
      if (lookahead == '3') ADVANCE(116);
      if (lookahead == '6') ADVANCE(117);
      END_STATE();
    case 102:
      if (lookahead == 'e') ADVANCE(38);
      END_STATE();
    case 103:
      if (lookahead == 'd') ADVANCE(118);
      END_STATE();
    case 104:
      if (lookahead == 'l') ADVANCE(119);
      END_STATE();
    case 105:
      if (lookahead == 't') ADVANCE(120);
      END_STATE();
    case 106:
      if (lookahead == 'c') ADVANCE(121);
      END_STATE();
    case 107:
      if (lookahead == 'e') ADVANCE(38);
      END_STATE();
    case 108:
      if (lookahead == 'n') ADVANCE(38);
      END_STATE();
    case 109:
      if (lookahead == 'o') ADVANCE(122);
      END_STATE();
    case 110:
      if (lookahead == 'g') ADVANCE(38);
      END_STATE();
    case 111:
      if (lookahead == 't') ADVANCE(38);
      END_STATE();
    case 112:
      if (lookahead == 'i') ADVANCE(123);
      if (lookahead == 'o') ADVANCE(124);
      END_STATE();
    case 113:
      if (lookahead == 't') ADVANCE(38);
      END_STATE();
    case 114:
      if (lookahead == 'u') ADVANCE(125);
      END_STATE();
    case 115:
      if (lookahead == 'l') ADVANCE(126);
      END_STATE();
    case 116:
      if (lookahead == '2') ADVANCE(38);
      END_STATE();
    case 117:
      if (lookahead == '4') ADVANCE(38);
      END_STATE();
    case 118:
      if (lookahead == 'e') ADVANCE(127);
      END_STATE();
    case 119:
      if (lookahead == 'i') ADVANCE(128);
      END_STATE();
    case 120:
      if (lookahead == 'o') ADVANCE(129);
      END_STATE();
    case 121:
      if (lookahead == 'o') ADVANCE(130);
      END_STATE();
    case 122:
      if (lookahead == 'f') ADVANCE(38);
      END_STATE();
    case 123:
      if (lookahead == 'n') ADVANCE(131);
      END_STATE();
    case 124:
      if (lookahead == 'f') ADVANCE(38);
      END_STATE();
    case 125:
      if (lookahead == 'e') ADVANCE(38);
      END_STATE();
    case 126:
      if (lookahead == 'a') ADVANCE(132);
      END_STATE();
    case 127:
      if (lookahead == 'x') ADVANCE(38);
      END_STATE();
    case 128:
      if (lookahead == 'n') ADVANCE(133);
      END_STATE();
    case 129:
      if (lookahead == 'r') ADVANCE(38);
      END_STATE();
    case 130:
      if (lookahead == 'n') ADVANCE(134);
      END_STATE();
    case 131:
      if (lookahead == 'f') ADVANCE(135);
      END_STATE();
    case 132:
      if (lookahead == 'g') ADVANCE(136);
      END_STATE();
    case 133:
      if (lookahead == 'e') ADVANCE(38);
      END_STATE();
    case 134:
      if (lookahead == 't') ADVANCE(137);
      END_STATE();
    case 135:
      if (lookahead == 'o') ADVANCE(38);
      END_STATE();
    case 136:
      if (lookahead == 's') ADVANCE(38);
      END_STATE();
    case 137:
      if (lookahead == 'e') ADVANCE(138);
      END_STATE();
    case 138:
      if (lookahead == 'x') ADVANCE(139);
      END_STATE();
    case 139:
      if (lookahead == 't') ADVANCE(38);
      END_STATE();
    default:
      return false;
  }
}

static const TSLexMode ts_lex_modes[STATE_COUNT] = {
  [0] = {.lex_state = 0},
  [1] = {.lex_state = 0},
  [2] = {.lex_state = 0},
  [3] = {.lex_state = 0},
  [4] = {.lex_state = 0},
};

static const uint16_t ts_parse_table[LARGE_STATE_COUNT][SYMBOL_COUNT] = {
  [0] = {
    [ts_builtin_sym_end] = ACTIONS(1),
    [sym_identifier] = ACTIONS(1),
    [sym_line_comment] = ACTIONS(3),
    [sym_block_comment] = ACTIONS(3),
    [sym_string] = ACTIONS(1),
    [sym_number] = ACTIONS(1),
    [sym_boolean] = ACTIONS(1),
    [sym_directive] = ACTIONS(1),
    [sym_keyword] = ACTIONS(1),
    [sym_operator] = ACTIONS(1),
    [sym_punctuation] = ACTIONS(1),
  },
  [1] = {
    [sym_source_file] = STATE(4),
    [sym__token] = STATE(2),
    [aux_sym_source_file_repeat1] = STATE(2),
    [ts_builtin_sym_end] = ACTIONS(5),
    [sym_identifier] = ACTIONS(7),
    [sym_line_comment] = ACTIONS(3),
    [sym_block_comment] = ACTIONS(3),
    [sym_string] = ACTIONS(9),
    [sym_number] = ACTIONS(9),
    [sym_boolean] = ACTIONS(7),
    [sym_directive] = ACTIONS(9),
    [sym_keyword] = ACTIONS(7),
    [sym_operator] = ACTIONS(7),
    [sym_punctuation] = ACTIONS(7),
  },
  [2] = {
    [sym__token] = STATE(3),
    [aux_sym_source_file_repeat1] = STATE(3),
    [ts_builtin_sym_end] = ACTIONS(11),
    [sym_identifier] = ACTIONS(13),
    [sym_line_comment] = ACTIONS(3),
    [sym_block_comment] = ACTIONS(3),
    [sym_string] = ACTIONS(15),
    [sym_number] = ACTIONS(15),
    [sym_boolean] = ACTIONS(13),
    [sym_directive] = ACTIONS(15),
    [sym_keyword] = ACTIONS(13),
    [sym_operator] = ACTIONS(13),
    [sym_punctuation] = ACTIONS(13),
  },
  [3] = {
    [sym__token] = STATE(3),
    [aux_sym_source_file_repeat1] = STATE(3),
    [ts_builtin_sym_end] = ACTIONS(17),
    [sym_identifier] = ACTIONS(19),
    [sym_line_comment] = ACTIONS(3),
    [sym_block_comment] = ACTIONS(3),
    [sym_string] = ACTIONS(22),
    [sym_number] = ACTIONS(22),
    [sym_boolean] = ACTIONS(19),
    [sym_directive] = ACTIONS(22),
    [sym_keyword] = ACTIONS(19),
    [sym_operator] = ACTIONS(19),
    [sym_punctuation] = ACTIONS(19),
  },
};

static const uint16_t ts_small_parse_table[] = {
  [0] = 2,
    ACTIONS(25), 1,
      ts_builtin_sym_end,
    ACTIONS(3), 2,
      sym_line_comment,
      sym_block_comment,
};

static const uint32_t ts_small_parse_table_map[] = {
  [SMALL_STATE(4)] = 0,
};

static const TSParseActionEntry ts_parse_actions[] = {
  [0] = {.entry = {.count = 0, .reusable = false}},
  [1] = {.entry = {.count = 1, .reusable = false}}, RECOVER(),
  [3] = {.entry = {.count = 1, .reusable = true}}, SHIFT_EXTRA(),
  [5] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_source_file, 0, 0, 0),
  [7] = {.entry = {.count = 1, .reusable = false}}, SHIFT(2),
  [9] = {.entry = {.count = 1, .reusable = true}}, SHIFT(2),
  [11] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_source_file, 1, 0, 0),
  [13] = {.entry = {.count = 1, .reusable = false}}, SHIFT(3),
  [15] = {.entry = {.count = 1, .reusable = true}}, SHIFT(3),
  [17] = {.entry = {.count = 1, .reusable = true}}, REDUCE(aux_sym_source_file_repeat1, 2, 0, 0),
  [19] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_source_file_repeat1, 2, 0, 0), SHIFT_REPEAT(3),
  [22] = {.entry = {.count = 2, .reusable = true}}, REDUCE(aux_sym_source_file_repeat1, 2, 0, 0), SHIFT_REPEAT(3),
  [25] = {.entry = {.count = 1, .reusable = true}},  ACCEPT_INPUT(),
};

#ifdef __cplusplus
extern "C" {
#endif
#ifdef TREE_SITTER_HIDE_SYMBOLS
#define TS_PUBLIC
#elif defined(_WIN32)
#define TS_PUBLIC __declspec(dllexport)
#else
#define TS_PUBLIC __attribute__((visibility("default")))
#endif

TS_PUBLIC const TSLanguage *tree_sitter_jai(void) {
  static const TSLanguage language = {
    .version = LANGUAGE_VERSION,
    .symbol_count = SYMBOL_COUNT,
    .alias_count = ALIAS_COUNT,
    .token_count = TOKEN_COUNT,
    .external_token_count = EXTERNAL_TOKEN_COUNT,
    .state_count = STATE_COUNT,
    .large_state_count = LARGE_STATE_COUNT,
    .production_id_count = PRODUCTION_ID_COUNT,
    .field_count = FIELD_COUNT,
    .max_alias_sequence_length = MAX_ALIAS_SEQUENCE_LENGTH,
    .parse_table = &ts_parse_table[0][0],
    .small_parse_table = ts_small_parse_table,
    .small_parse_table_map = ts_small_parse_table_map,
    .parse_actions = ts_parse_actions,
    .symbol_names = ts_symbol_names,
    .symbol_metadata = ts_symbol_metadata,
    .public_symbol_map = ts_symbol_map,
    .alias_map = ts_non_terminal_alias_map,
    .alias_sequences = &ts_alias_sequences[0][0],
    .lex_modes = ts_lex_modes,
    .lex_fn = ts_lex,
    .keyword_lex_fn = ts_lex_keywords,
    .keyword_capture_token = sym_identifier,
    .primary_state_ids = ts_primary_state_ids,
  };
  return &language;
}
#ifdef __cplusplus
}
#endif
