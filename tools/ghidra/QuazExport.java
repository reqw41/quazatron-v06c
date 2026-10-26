// Ghidra (консольный режим): засеять код по покрытию трассы, создать функции по целям call,
// выгрузить функции с вызывающими и ссылки на данные. Аргументы: <cov_pcs.txt> <calls.txt> <out_dir>
import ghidra.app.script.GhidraScript;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class QuazExport extends GhidraScript {
    Address a(int x) { return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(x); }
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        AddressSet seeds = new AddressSet();
        for (String l : Files.readAllLines(Paths.get(args[0]))) {
            l = l.trim(); if (l.matches("[0-9A-F]{4}")) seeds.add(a(Integer.parseInt(l, 16)));
        }
        new DisassembleCommand(seeds, null, true).applyTo(currentProgram, monitor);
        for (String l : Files.readAllLines(Paths.get(args[1]))) {
            l = l.trim(); if (!l.matches("[0-9A-F]{4}")) continue;
            Address e = a(Integer.parseInt(l, 16));
            if (getFunctionAt(e) == null) createFunction(e, null);
        }
        analyzeChanges(currentProgram);
        String out = args[2];
        try (PrintWriter fw = new PrintWriter(out + "/ghidra_funcs.txt")) {
            for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                StringBuilder sb = new StringBuilder();
                for (Function c : f.getCallingFunctions(monitor)) sb.append(' ').append(c.getEntryPoint());
                StringBuilder rg = new StringBuilder();
                for (AddressRange r : f.getBody()) rg.append(' ').append(r.getMinAddress()).append('-').append(r.getMaxAddress());
                fw.printf("%s %d callers:%s body:%s%n", f.getEntryPoint(), f.getBody().getNumAddresses(), sb, rg);
            }
        }
        try (PrintWriter cw = new PrintWriter(out + "/ghidra_code.txt")) {
            // все команды: адрес, длина, текст — для карты код/данные и поиска косвенных переходов
            for (Instruction ins : currentProgram.getListing().getInstructions(true))
                cw.printf("%s %d %s%n", ins.getAddress(), ins.getLength(), ins.toString());
        }
        try (PrintWriter dw = new PrintWriter(out + "/ghidra_xrefs.txt")) {
            ReferenceManager rm = currentProgram.getReferenceManager();
            Listing ls = currentProgram.getListing();
            for (Instruction ins : ls.getInstructions(true)) {
                for (Reference r : ins.getReferencesFrom()) {
                    Function f = getFunctionContaining(ins.getAddress());
                    dw.printf("%s %s %s %s [%s]%n", r.getToAddress(), r.getReferenceType(), ins.getAddress(),
                              f == null ? "-" : f.getEntryPoint().toString(), ins.toString());
                }
            }
        }
    }
}
