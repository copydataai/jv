# JV Examples

## Explain Before Running

```bash
jv explain
jv run
```

`jv explain` prints the same plan `jv run` will execute without compiling or running the program.

## Diagnose A Project

```bash
jv doctor
jv doctor --json
```

Use `jv doctor` when JV surprises you. It prints what JV detected, why it selected a main class, which command it would run, and what blocks execution. Use `jv doctor --json` when agents or scripts need the same project model as structured data.

## Inspect Recent JV Activity

```bash
jv history
jv history --failures
jv history --json
```

Use `jv history` to see recent runs from generated `.jv/` memory. `--failures` narrows the view to blocked or failed runs, and `--json` prints normalized records for agents and scripts.

## Retry The Last Failure

```bash
jv run
# fix the compiler error or blocked project state
jv retry
```

Use `jv retry --dry-run` to inspect the selected retry command before executing it. Use `jv retry --json` when an agent needs the latest retryable failure as structured data.

## Watch While Editing

```bash
jv watch
jv watch com.example.App alpha beta
```

`jv watch` runs once immediately, then reruns when Java source files change. Failed builds stay in watch mode so the next edit can recover.

## Multiple Main Classes

```bash
jv doctor
jv run com.example.App
jv remember main com.example.App
jv run
```

## Example 1: Simple Hello World (No Package)

```bash
jv create hello-world
cd hello-world
jv run
```

Output:
```
Hello from JV!
```

## Example 2: University Assignment with Packages

Create a program in package `ie.atu.sw` (common for Irish universities):

### Method 1: Using the package argument
```bash
jv create my-assignment ie.atu.sw
cd my-assignment
jv run ie.atu.sw.Main
```

### Method 2: Interactive prompt
```bash
jv create my-assignment
# When prompted, enter: ie.atu.sw
cd my-assignment
jv run ie.atu.sw.Main
```

### Method 3: Manual package creation
```bash
jv create my-assignment
cd my-assignment
```

Create the package structure and file:
```bash
mkdir -p src/ie/atu/sw
cat > src/ie/atu/sw/StudentApp.java << 'EOF'
package ie.atu.sw;

public class StudentApp {
    public static void main(String[] args) {
        System.out.println("Student Management System");
        System.out.println("========================");
        
        Student s1 = new Student("John Doe", "G00123456");
        s1.display();
    }
}

class Student {
    private String name;
    private String id;
    
    public Student(String name, String id) {
        this.name = name;
        this.id = id;
    }
    
    public void display() {
        System.out.println("Name: " + name);
        System.out.println("ID: " + id);
    }
}
EOF
```

Compile and run:
```bash
jv compile
jv run ie.atu.sw.StudentApp
```

## Example 3: Command-Line Arguments

```bash
jv create calculator
cd calculator
cat > src/Calculator.java << 'EOF'
public class Calculator {
    public static void main(String[] args) {
        if (args.length < 3) {
            System.out.println("Usage: java Calculator <num1> <op> <num2>");
            System.out.println("Example: java Calculator 5 + 3");
            return;
        }
        
        double num1 = Double.parseDouble(args[0]);
        String op = args[1];
        double num2 = Double.parseDouble(args[2]);
        
        double result = 0;
        switch (op) {
            case "+": result = num1 + num2; break;
            case "-": result = num1 - num2; break;
            case "*": result = num1 * num2; break;
            case "/": result = num1 / num2; break;
            default:
                System.out.println("Unknown operator: " + op);
                return;
        }
        
        System.out.println(num1 + " " + op + " " + num2 + " = " + result);
    }
}
EOF

jv run Calculator 10 + 5
jv run Calculator 20 / 4
```

## Example 4: Using External Libraries

Download a library (e.g., JSON processing):

```bash
jv create json-example
cd json-example

# Download a library (example with minimal-json)
curl -L https://repo1.maven.org/maven2/com/eclipsesource/minimal-json/minimal-json/0.9.5/minimal-json-0.9.5.jar \
  -o lib/minimal-json.jar

# Create a program that uses it
cat > src/JsonExample.java << 'EOF'
import com.eclipsesource.json.Json;
import com.eclipsesource.json.JsonObject;

public class JsonExample {
    public static void main(String[] args) {
        JsonObject person = Json.object()
            .add("name", "John")
            .add("age", 21)
            .add("student", true);
        
        System.out.println(person.toString());
    }
}
EOF

jv compile
jv run JsonExample
```

## Example 5: Multi-Class Project

```bash
jv create shapes
cd shapes

mkdir -p src/shapes
cat > src/shapes/Shape.java << 'EOF'
package shapes;

public abstract class Shape {
    public abstract double area();
    public abstract double perimeter();
}
EOF

cat > src/shapes/Circle.java << 'EOF'
package shapes;

public class Circle extends Shape {
    private double radius;
    
    public Circle(double radius) {
        this.radius = radius;
    }
    
    public double area() {
        return Math.PI * radius * radius;
    }
    
    public double perimeter() {
        return 2 * Math.PI * radius;
    }
}
EOF

cat > src/shapes/Rectangle.java << 'EOF'
package shapes;

public class Rectangle extends Shape {
    private double width;
    private double height;
    
    public Rectangle(double width, double height) {
        this.width = width;
        this.height = height;
    }
    
    public double area() {
        return width * height;
    }
    
    public double perimeter() {
        return 2 * (width + height);
    }
}
EOF

cat > src/ShapeDemo.java << 'EOF'
import shapes.*;

public class ShapeDemo {
    public static void main(String[] args) {
        Circle c = new Circle(5);
        Rectangle r = new Rectangle(4, 6);
        
        System.out.println("Circle:");
        System.out.println("  Area: " + c.area());
        System.out.println("  Perimeter: " + c.perimeter());
        
        System.out.println("\nRectangle:");
        System.out.println("  Area: " + r.area());
        System.out.println("  Perimeter: " + r.perimeter());
    }
}
EOF

jv compile
jv run ShapeDemo
```

## Example 6: Quick Iteration Workflow

The typical workflow for assignments:

```bash
# Create project
jv create lab-week-3
cd lab-week-3

# Edit in your favorite editor
vim src/Main.java

# Compile and run (jv auto-compiles if needed)
jv run Main

# Make changes
vim src/Main.java

# Run again (auto-recompiles)
jv run Main

# Clean when done
jv clean
```

## Tips

1. **Auto-compilation**: `jv run` automatically compiles if sources are newer
2. **Package structure**: Create directories matching your package names
3. **External JARs**: Just drop them in the `lib/` folder
4. **Multiple files**: `jv compile` finds all .java files automatically
5. **Clean builds**: Use `jv clean` if you get weird compilation errors

## Common University Packages

Different universities use different package conventions:

- **ATU (Galway)**: `ie.atu.sw`
- **UCD**: `ie.ucd.cs`
- **Trinity**: `ie.tcd.cs`
- **MIT**: `edu.mit.cs`

Just create the matching directory structure in `src/` and you're good to go!
