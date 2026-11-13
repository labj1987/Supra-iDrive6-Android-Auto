// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: Copyright (c) 2026 nanaisu - NBT-AAD (https://github.com/Sq00ky/Supra-iDrive6-Android-Auto)
// Host test for src/env_file.hpp: the daemon reads every setting of nbt-aad.env itself (no 15-setting limit).

#include "env_file.hpp"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <string>

int main() {
    // 1. The launchers' line rule: comments, blanks and trailing CR / spaces; the value keeps inner '='.
    int skipped = -1;
    std::vector<nbt::envfile::Entry> e =
        nbt::envfile::parse("# comment\n\nA=1\r\nB=x=y  \nnot a setting\n=novalue\nBAD NAME=1\nC=", &skipped);
    assert(e.size() == 3);
    assert(e[0].name == "A" && e[0].value == "1");
    assert(e[1].name == "B" && e[1].value == "x=y");
    assert(e[2].name == "C" && e[2].value.empty());
    assert(skipped == 3);

    // 2. More than 15 settings and a long value: all of them come through (the old launchers kept 15 x 159 chars).
    std::string many;
    for (int i = 0; i < 40; ++i) {
        char line[64];
        snprintf(line, sizeof line, "NBT_TEST_%02d=%d\n", i, i);
        many += line;
    }
    std::string longValue(400, 'v');
    many += "NBT_TEST_LONG=" + longValue + "\n";
    many += "NBT_TEST_LAST=1\n";
    e = nbt::envfile::parse(many, NULL);
    assert(e.size() == 42);
    assert(e[40].value == longValue);
    assert(e[41].name == "NBT_TEST_LAST");

    // 3. apply(): sets what is missing, keeps what the launcher / shell already set, first occurrence wins.
    char path[] = "/tmp/nbt_env_file_testXXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0);
    std::string text = many + "NBT_TEST_KEEP=file\nNBT_TEST_DUP=first\nNBT_TEST_DUP=second\n";
    assert(write(fd, text.data(), text.size()) == (ssize_t)text.size());
    close(fd);
    setenv("NBT_TEST_KEEP", "launcher", 1);
    unsetenv("NBT_TEST_LAST");
    unsetenv("NBT_TEST_DUP");
    nbt::envfile::Result r = nbt::envfile::apply(path);
    unlink(path);
    assert(r.found);
    assert(r.settings == 45);
    assert(r.added == 43);   // all but NBT_TEST_KEEP (already set) and the second NBT_TEST_DUP
    assert(!strcmp(getenv("NBT_TEST_LAST"), "1"));
    assert(!strcmp(getenv("NBT_TEST_KEEP"), "launcher"));
    assert(!strcmp(getenv("NBT_TEST_DUP"), "first"));
    assert(strlen(getenv("NBT_TEST_LONG")) == 400);

    // 4. No file: nothing happens.
    r = nbt::envfile::apply("/nonexistent/nbt-aad.env");
    assert(!r.found && r.settings == 0 && r.added == 0);

    printf("test_env_file: all checks passed\n");
    return 0;
}
