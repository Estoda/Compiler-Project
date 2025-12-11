%{
#include <stdio.h>
#include <string.h>

int yylex(void);
void yyerror(char *);
extern int yylineno;
extern FILE* yyin;
extern FILE* yyout;
FILE* yytree = NULL;
FILE* yyError = NULL;

int sym[256]; /* enough for many vars (IDs assigned by scanner) */

#define MAX_DEPTH 256
char prefix[MAX_DEPTH][16];
int depth = 0;

void pushPrefix(const char* p)
{
    strcpy(prefix[depth], p);
    depth++;
}

void popPrefix() {
    depth--;
}

void printTreeNode(const char* label)
{
    for(int i = 0; i < depth; i++)
        fprintf(yytree, "%s", prefix[i]);
    
    fprintf(yytree, "%s\n", label);
}

%}

%union {
    int ival;
    float fval;
    char* sval;
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

/* nonterm types */
%type<ival> expr condition

/* precedence & dangling-else */
%nonassoc LOWER_ELSE
%right '='
%left '+' '-'
%left '*' '/'

%%

program:
      stmts
    ;

/* zero or more statements */
stmts:
      /* empty */
    | stmts stmt
    ;

stmt:
      declaration
    | assignment
    | printStatement
    | IfStatement
    | expr ';'       { printTreeNode("EXPR_STMT");fprintf(yyout, "%d\n", $1); }
    ;

/* declaration and assignment use literal '=' and ';' */
declaration:
      INT VARIABLE '=' expr ';'
      {
          printTreeNode("DECLARATION");
          pushPrefix("|   "); printTreeNode("int");
          printTreeNode("var");
          printTreeNode("expr");
          popPrefix();

          sym[$2] = $4;
          fprintf(yyout, "Declared var[%d] = %d\n", $2, $4);
      }
    ;

assignment:
      VARIABLE '=' expr ';'
      {
          printTreeNode("ASSIGN");
          pushPrefix("└──");
          printTreeNode("var");
          printTreeNode("expr");
          popPrefix();

          sym[$1] = $3;
          fprintf(yyout, "Assigned var[%d] = %d\n", $1, $3);
      }
    ;

printStatement:
      PRINT '(' expr ')' ';'
      {
          printTreeNode("PRINT");
          pushPrefix("└──");
          printTreeNode("expr");
          popPrefix();

          fprintf(yyout, "Print: %d\n", $3);
      }
    ;

/* If without else uses LOWER_ELSE to avoid dangling-else */
IfStatement:
    IF '(' condition ')' ':' block ELSE ':' block END
      {
          printTreeNode("IF");
          
          /* CONDITION subtree */
          pushPrefix("└──");
            printTreeNode("CONDITION");
            pushPrefix("└──");
                printTreeNode($3 ? "true" : "false");
            popPrefix();
          popPrefix();

          /* THEN block */
          pushPrefix("└──");
            printTreeNode("THEN");
          popPrefix();

          /* ELSE block */
          printTreeNode("ELSE");

          printTreeNode("END");
      }
      | IF '(' condition ')' ':' block %prec LOWER_ELSE END
      {
          printTreeNode("IF");
          pushPrefix("└──");
            printTreeNode("CONDITION");
            pushPrefix("└──");
                printTreeNode($3 ? "true" : "false");
            popPrefix();
          popPrefix();

          printTreeNode("THEN");
          printTreeNode("END");
      }
    ;

/* block is a sequence of statements (no special newline token) */
block:
    {
          pushPrefix("└──");
    }
      stmts
    {
          popPrefix();
    }
    ;

/* condition returns 0 or 1 */
condition:
      expr OP expr
      {
          printTreeNode("CONDITION");
          pushPrefix("└──");

          printTreeNode($2);

          popPrefix();

          char *op = $2;
          if (strcmp(op, "==") == 0)      $$ = ($1 == $3);
          else if (strcmp(op, "!=") == 0) $$ = ($1 != $3);
          else if (strcmp(op, "<=") == 0) $$ = ($1 <= $3);
          else if (strcmp(op, ">=") == 0) $$ = ($1 >= $3);
          else if (strcmp(op, "<") == 0)  $$ = ($1 <  $3);
          else if (strcmp(op, ">") == 0)  $$ = ($1 >  $3);
          else {
              yyerror("Unknown operator");
              $$ = 0;
          }
      }
    ;

/* arithmetic expressions */
expr:
      INTEGER   {
          char buf[64];
          sprintf(buf, "INTEGER(%d)", $1);
          printTreeNode(buf);
          $$ = $1;
      }
    | VARIABLE              {
                  char buf[64];
          sprintf(buf, "VAR(id=%d)", $1);
          printTreeNode(buf);
          $$ = sym[$1];
    }
    | expr '+' expr        { printTreeNode("+");$$ = $1 + $3; }
    | expr '-' expr        { printTreeNode("-");$$ = $1 - $3; }
    | expr '*' expr        { printTreeNode("*");$$ = $1 * $3; }
    | expr '/' expr        { printTreeNode("/");$$ = $1 / $3; }
    | '(' expr ')'         { printTreeNode("(expr)");$$ = $2; }
    ;

%%

void yyerror(char *s) {
    if (!yyError) yyError = stderr;
    fprintf(yyError, "Error: %s at line %d\n", s, yylineno);
}

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
