%{
/*
  parser.y — Statements & correct if/else execution

  Behaviors:
  - Build statement trees during parsing (no execution during parse)
  - After parsing the whole program, execute top-level statements (program -> stmts { execute_list($1); })
  - Blocks inside if/else are kept as stmt-lists and only executed according to condition
  - Printing of parse-trees goes to tree.txt at execution time
  - Runtime outputs (Declared..., Assigned..., Print...) go to out.txt
  - Errors go to outError.txt
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int yylex(void);
void yyerror(char *);

extern int yylineno;
extern FILE* yyin;
extern FILE* yyout;
FILE* yytree = NULL;
FILE* yyError = NULL;

/* symbol table: variables are represented by integer IDs provided by scanner */
int sym[256];

int runtime_error = 0;

/* Node kinds */
enum {
    N_UNKNOWN = 0,
    N_INT,
    N_VAR,
    N_OP,       /* arithmetic or comparison operator node */
    N_DECL,     /* declaration (dec) */
    N_ASSIGN,   /* assign */
    N_PRINT,    /* print */
    N_IF,       /* if */
    N_BRANCHES, /* helper node with then/else as children */
    N_STMTLIST  /* linked list tree of statements: left = previous list, right = stmt */
};

/* ---- Node definition ---- */
typedef struct Node {
    char *label;          /* human-readable label (operator or node name) */
    struct Node *left;
    struct Node *right;
    int kind;
    int int_value;        /* for integer literal */
    int var_id;           /* for variable nodes */
} Node;

/* helpers to create nodes */
Node* new_node_kind(const char *label, int kind, Node *left, Node *right) {
    Node *n = (Node*)malloc(sizeof(Node));
    if (!n) { perror("malloc"); exit(1); }
    n->label = strdup(label ? label : "");
    n->left = left;
    n->right = right;
    n->kind = kind;
    n->int_value = 0;
    n->var_id = -1;
    return n;
}

Node* new_int_node(int v) {
    Node *n = new_node_kind(NULL, N_INT, NULL, NULL);
    {
        char buf[64];
        sprintf(buf, "INTEGER(%d)", v);
        free(n->label);
        n->label = strdup(buf);
    }
    n->int_value = v;
    return n;
}

Node* new_var_node(int id) {
    Node *n = new_node_kind(NULL, N_VAR, NULL, NULL);
    {
        char buf[64];
        sprintf(buf, "VAR(id=%d)", id);
        free(n->label);
        n->label = strdup(buf);
    }
    n->var_id = id;
    return n;
}

Node* new_op_node(const char *op, Node *l, Node *r) {
    Node *n = new_node_kind(op, N_OP, l, r);
    return n;
}

Node* new_decl_node(Node *varNode, Node *exprNode) {
    return new_node_kind("dec", N_DECL, varNode, exprNode);
}

Node* new_assign_node(Node *varNode, Node *exprNode) {
    return new_node_kind("assign", N_ASSIGN, varNode, exprNode);
}

Node* new_print_node(Node *exprNode) {
    return new_node_kind("print", N_PRINT, exprNode, NULL);
}

Node* new_if_node(Node *cond, Node *thenList, Node *elseList) {
    Node *branches = new_node_kind("branches", N_BRANCHES, thenList, elseList);
    return new_node_kind("if", N_IF, cond, branches);
}

Node* new_stmtlist_node(Node *prevList, Node *stmt) {
    return new_node_kind("stmtlist", N_STMTLIST, prevList, stmt);
}

/* free tree */
void free_tree(Node *n) {
    if (!n) return;
    free_tree(n->left);
    free_tree(n->right);
    if (n->label) free(n->label);
    free(n);
}

/* ---- printing rotated vertical tree to yytree (like doctor style) ---- */
void printTreeVertical(Node *root, int space) {
    if (root == NULL) return;

    if(root->kind == N_STMTLIST)
    {
        printTreeVertical(root->left, space);
        printTreeVertical(root->right, space);
        return;
    }

    int spacing_per_level = 5;
    space += spacing_per_level;

    printTreeVertical(root->right, space);

    fprintf(yytree, "\n");
    for (int i = spacing_per_level; i < space; i++)
        fprintf(yytree, " ");
    fprintf(yytree, "%s\n", root->label);

    printTreeVertical(root->left, space);
}

/* print top-level separation */
void print_tree_header(Node *n) {
    if (!n) return;

    if(n->kind == N_STMTLIST)
    {
        print_tree_header(n->left);
        print_tree_header(n->right);
        return;
    }

    printTreeVertical(n, 0);
    fprintf(yytree, "\n--------------------------------------------------\n\n");
}

/* ---- evaluation of expressions at execution time ---- */
int eval_expr(Node *n) {
    if (!n) return 0;
    switch (n->kind) {
        case N_INT:
            return n->int_value;
        case N_VAR:
            if (n->var_id >=0 && n->var_id < 256) return sym[n->var_id];
            return 0;
        case N_OP: {
            int L = eval_expr(n->left);
            int R = eval_expr(n->right);
            /* arithmetic */
            if (strcmp(n->label, "+") == 0) return L + R;
            if (strcmp(n->label, "-") == 0) return L - R;
            if (strcmp(n->label, "*") == 0) return L * R;
            if (strcmp(n->label, "/") == 0) {
                if (R == 0) { yyerror("Division by zero"); runtime_error = 1; return 0; }
                return L / R;
            }
            /* comparisons -> return 0/1 */
            if (strcmp(n->label, "==") == 0) return (L == R);
            if (strcmp(n->label, "!=") == 0) return (L != R);
            if (strcmp(n->label, "<=") == 0) return (L <= R);
            if (strcmp(n->label, ">=") == 0) return (L >= R);
            if (strcmp(n->label, "<") == 0) return (L < R);
            if (strcmp(n->label, ">") == 0) return (L > R);
            /* unknown op */
            yyerror("Unknown operator in eval_expr");
            return 0;
        }
        default:
            yyerror("eval_expr: expected expression node");
            return 0;
    }
}

/* Forward declarations */
void execute_stmt(Node *stmt);
void execute_list(Node *list);

/* execute a single statement node */
void execute_stmt(Node *stmt) {
    if (!stmt) return;
    

    /* Print the statement tree to tree.txt before executing (so tree.txt reflects executed statements) */
    print_tree_header(stmt);

    switch (stmt->kind) {
        case N_DECL: {
            /* left is var node, right is expression node */
            runtime_error = 0;
            int v = eval_expr(stmt->right);
            if (runtime_error) return;
            Node *varNode = stmt->left;
            Node *exprNode = stmt->right;
            int val = eval_expr(exprNode);
            if (varNode->kind == N_VAR) {
                int id = varNode->var_id;
                sym[id] = val;
                fprintf(yyout, "Declared var[%d] = %d\n", id, val);
            } else {
                yyerror("Declaration left side is not a variable");
            }
            break;
        }
        case N_ASSIGN: {
            runtime_error = 0;
            int v = eval_expr(stmt->right);
            if (runtime_error) return;
            Node *varNode = stmt->left;
            Node *exprNode = stmt->right;
            int val = eval_expr(exprNode);
            if (varNode->kind == N_VAR) {
                int id = varNode->var_id;
                sym[id] = val;
                fprintf(yyout, "Assigned var[%d] = %d\n", id, val);
            } else {
                yyerror("Assignment left side is not a variable");
            }
            break;
        }
        case N_PRINT: {
            runtime_error = 0;
            int v = eval_expr(stmt->left);
            if (runtime_error) return;
            Node *exprNode = stmt->left;
            int val = eval_expr(exprNode);
            fprintf(yyout, "Print: %d\n", val);
            break;
        }
        case N_IF: {
            runtime_error = 0;
            int v = eval_expr(stmt->left);
            if (runtime_error) return;
            Node *cond = stmt->left;
            Node *branches = stmt->right; /* branches node: left=thenList, right=elseList */
            int cond_val = eval_expr(cond);
            if (branches && branches->kind == N_BRANCHES) {
                Node *thenList = branches->left;
                Node *elseList = branches->right;
                if (cond_val) {
                    execute_list(thenList);
                } else {
                    execute_list(elseList);
                }
            } else {
                yyerror("If branches malformed");
            }
            break;
        }
        case N_STMTLIST: {
            /* If accidentally a stmtlist passed directly, execute it */
            execute_list(stmt);
            break;
        }
        default:
            yyerror("Unknown statement kind in execute_stmt");
            break;
    }
}

/* execute a list-of-statements node (stmtlist) */
void execute_list(Node *list) {
    if (!list) return;
    if (list->kind == N_STMTLIST) {
        /* left may be previous list (or NULL), right is a statement */
        execute_list(list->left);
        execute_stmt(list->right);
    } else {
        /* single statement */
        execute_stmt(list);
    }
}

%}

/* Bison declarations */
%union {
    int ival;
    float fval;
    char* sval;
    struct Node* node;
}

/* tokens */
%token<ival> INTEGER
%token<ival> VARIABLE
%token PRINT
%token IF
%token ELSE
%token INT
%token END
%token<sval> OP

/* nonterminals that carry Node* */
%type<node> program stmts stmt declaration assignment printStatement IfStatement block condition expr

/* precedence & dangling-else */
%nonassoc LOWER_ELSE
%right '='
%left '+' '-'
%left '*' '/'

%%

program:
      stmts
      {
          /* execute top-level statements after parsing */
          execute_list($1);
      }
    ;

/* stmts forms a stmt-list (or NULL) */
stmts:
      /* empty */   { $$ = NULL; }
    | stmts stmt    {
                        /* append stmt to list: if $1 == NULL return stmt as list node or create list node */
                        if ($1 == NULL) {
                            /* treat single stmt as list (we still wrap it into a stmtlist node to be uniform) */
                            $$ = new_stmtlist_node(NULL, $2);
                        } else {
                            $$ = new_stmtlist_node($1, $2);
                        }
                    }
    ;

/* a statement returns a Node* (no execution here) */
stmt:
      declaration  { $$ = $1; }
    | assignment   { $$ = $1; }
    | printStatement { $$ = $1; }
    | IfStatement  { $$ = $1; }
    | expr ';'     { /* expression statement: evaluate at execution time; wrap as a print of value? we keep it as an expr node to be executed as printing its value */
                      /* We'll wrap it in a print-like node to keep execution consistent: a "printexpr" -> we'll use N_PRINT with left = expr */
                      $$ = new_print_node($1);
                    }
    ;

/* declaration: INT VARIABLE '=' expr ';' */
declaration:
      INT VARIABLE '=' expr ';'
      {
          /* var node with id */
          Node *varNode = new_var_node($2);
          Node *dec = new_decl_node(varNode, $4);
          $$ = dec;
      }
    ;

/* assignment: VARIABLE '=' expr ';' */
assignment:
      VARIABLE '=' expr ';'
      {
          Node *varNode = new_var_node($1);
          Node *asn = new_assign_node(varNode, $3);
          $$ = asn;
      }
    ;

/* printStatement: PRINT '(' expr ')' ';' */
printStatement:
      PRINT '(' expr ')' ';'
      {
          Node *p = new_print_node($3);
          $$ = p;
      }
    ;

/* If with and without else: build if node (no execution here) */
IfStatement:
    IF '(' condition ')' ':' block ELSE ':' block END
      {
          Node *ifn = new_if_node($3, $6, $9);
          $$ = ifn;
      }
    | IF '(' condition ')' ':' block %prec LOWER_ELSE END
      {
          Node *ifn = new_if_node($3, $6, NULL);
          $$ = ifn;
      }
    ;

/* block yields the stmtlist (or NULL) */
block:
      stmts
      {
          $$ = $1;  /* block is simply the stmtlist produced */
      }
    ;

/* condition: produce expression-op node (left op right) */
condition:
      expr OP expr
      {
          /* OP is a string (lexer must strdup) */
          $$ = new_op_node($2, $1, $3);
          /* We do not evaluate now; evaluation happens at run-time via eval_expr */
          free($2); /* free strdup from lexer to avoid leak */
      }
    ;

/* arithmetic expressions: build expression tree (no runtime evaluation now) */
expr:
      INTEGER
      {
          $$ = new_int_node($1);
      }
    | VARIABLE
      {
          $$ = new_var_node($1);
      }
    | expr '+' expr
      {
          $$ = new_op_node("+", $1, $3);
      }
    | expr '-' expr
      {
          $$ = new_op_node("-", $1, $3);
      }
    | expr '*' expr
      {
          $$ = new_op_node("*", $1, $3);
      }
    | expr '/' expr
      {
          $$ = new_op_node("/", $1, $3);
      }
    | '(' expr ')'
      {
          $$ = $2;
      }
    ;

%%

/* error reporting */
void yyerror(char *s) {
    if (!yyError) yyError = stderr;
    fprintf(yyError, "Error: %s at line %d\n", s, yylineno);
}

/* main: open files and run parser */
int main(void) {
    yyin = fopen("in.txt", "r");
    yyout = fopen("out.txt", "w");
    yytree = fopen("tree.txt", "w");
    yyError = fopen("outError.txt", "w");

    if (!yyin) { perror("open in.txt"); return 1; }
    if (!yyout) { perror("open out.txt"); return 1; }
    if (!yytree) { perror("open tree.txt"); return 1; }

    yyparse();

    fclose(yyin);
    fclose(yyout);
    fclose(yytree);
    if (yyError && yyError != stderr) fclose(yyError);
    return 0;
}
