# Compiler Project - Fayoum University

**Course:** Compiler Construction (4th Year, First Term, 2025/2026)  
**Team:** Dr. Fawzya Ramadan, Abdelrahman Salem, Ahmed Ibrahim  
**Project Title:** Full Compiler using FLEX and BISON

---

## 1. Overview

This project implements a **full compiler** for a custom programming language.  
The compiler performs:

- Lexical analysis using **FLEX**
- Syntax analysis using **BISON**
- Semantic checks for undeclared variables
- Runtime execution of statements
- Syntax tree generation (for extra credit)

**Input:** Source code in the custom language (text file `in.txt`)  
**Output:**

- `out.txt` → runtime outputs
- `tree.txt` → rotated syntax tree of the program
- `outError.txt` → semantic and runtime errors

---

## 2. Language Features

The custom language supports:

- Variable declaration and assignment:

  ```text
  int x = 5;
  y = 3;
  ```

- Arithmetic operations: `- + * /`

- Comparison operations: `== != > >= < <=`

- If-else statements with optional else block

  ```text
    if (x > y):
        x = x + 1;
    else:
        y = y + 1;
    end
  ```

- Print statements:
  ```text
  print(x);
  ```

**Notes:**

- Variable must be declared before assignment.
- Division by zero and usage of undeclared variables trigger semantic/runtime errors.

---

## 3. Project Structure

Project/
├─ scanner.l # FLEX lexer
├─ parser.y # BISON parser & runtime
├─ in.txt # Example input program
├─ out.txt # Runtime output
├─ tree.txt # Syntax tree output
├─ outError.txt # Errors (semantic/runtime)
├─ run.bat # running commands
├─ README.md
