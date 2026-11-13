// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: Copyright (c) 2026 nanaisu - NBT-AAD (https://github.com/Sq00ky/Supra-iDrive6-Android-Auto)
#ifndef NBT_ENV_FILE_HPP
#define NBT_ENV_FILE_HPP

// /opt/aa/nbt-aad.env read by the daemon itself. The launchers (iDrive app, plugin) used to pass only the first 15
// settings of the file, each cut at 159 characters, and dropped the rest without a word, so a setting near the end
// (NBT_KEEP_PF, appended by pf_aa) could silently not apply. Reading the file here makes every setting apply whoever
// starts the daemon; a variable already in the environment (launcher or shell) keeps its value.
//
// Same line rule as the launchers: one NAME=value per line, trailing CR / LF / spaces removed, blank lines and lines
// starting with '#' skipped. A line whose name is not [A-Za-z0-9_]+ is skipped too.
//
// parse() is pure text logic: host test tests/test_env_file.cpp.

#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <vector>

namespace nbt {
namespace envfile {

// The file is nbt::confFile(nbt::kDaemonEnvName) (nbt_paths.hpp): /opt/aa/nbt-aad.env, or the data dir in a package.

struct Entry {
    std::string name;
    std::string value;
};

inline bool validName(const std::string& n) {
    if (n.empty()) return false;
    for (size_t i = 0; i < n.size(); ++i) {
        char c = n[i];
        bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
        if (!ok) return false;
    }
    return true;
}

// Every setting of the file, in order. skipped (optional): lines that are not comments or blank but not NAME=value.
inline std::vector<Entry> parse(const std::string& text, int* skipped) {
    std::vector<Entry> out;
    int bad = 0;
    size_t start = 0;
    while (start < text.size()) {
        size_t end = text.find('\n', start);
        if (end == std::string::npos) end = text.size();
        std::string line = text.substr(start, end - start);
        start = end + 1;
        size_t l = line.size();
        while (l && (line[l - 1] == '\r' || line[l - 1] == ' ')) --l;
        line.erase(l);
        if (line.empty() || line[0] == '#') continue;
        size_t eq = line.find('=');
        if (eq == std::string::npos || !validName(line.substr(0, eq))) {
            ++bad;
            continue;
        }
        Entry e;
        e.name = line.substr(0, eq);
        e.value = line.substr(eq + 1);
        out.push_back(e);
    }
    if (skipped) *skipped = bad;
    return out;
}

struct Result {
    bool found;     // the file could be read
    int settings;   // NAME=value lines in it
    int added;      // set here because the launcher had not passed them
    int skipped;    // malformed lines
};

// Reads the file and setenv()s each setting the environment does not have yet. Call before any thread starts.
inline Result apply(const char* path) {
    Result r = { false, 0, 0, 0 };
    FILE* f = fopen(path, "r");
    if (!f) return r;
    r.found = true;
    std::string text;
    char buf[512];
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) text.append(buf, n);
    fclose(f);
    std::vector<Entry> es = parse(text, &r.skipped);
    r.settings = (int)es.size();
    for (size_t i = 0; i < es.size(); ++i) {
        if (getenv(es[i].name.c_str())) continue;
        if (setenv(es[i].name.c_str(), es[i].value.c_str(), 0) == 0) ++r.added;
    }
    return r;
}

}  // namespace envfile
}  // namespace nbt

#endif
