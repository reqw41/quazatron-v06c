// Ghidra (консольный режим): декомпиляция всех функций в build/decomp/<адрес>.c
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import java.io.*;

public class QuazDecomp extends GhidraScript {
    @Override
    public void run() throws Exception {
        String out = getScriptArgs()[0];
        new File(out).mkdirs();
        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            DecompileResults r = di.decompileFunction(f, 60, monitor);
            String txt = r.decompileCompleted() ? r.getDecompiledFunction().getC() : "// не декомпилировалось: " + r.getErrorMessage();
            try (PrintWriter w = new PrintWriter(out + "/" + f.getEntryPoint().toString().replace("ram:", "") + ".c")) { w.print(txt); }
        }
    }
}
