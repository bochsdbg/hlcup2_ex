CONFIG -= qt
CONFIG += c++17

INCLUDEPATH += /usr/lib/erlang/erts-10.4.4/include/

HEADERS += miniz.h \
    Account.hpp \
    AccountParser.hpp \
    common.hpp

SOURCES += \
    main.cpp \
    miniz.c \
    nifs.cpp

LIBS += -L/usr/lib/erlang/lib/erl_interface-3.12/lib -lerl_interface -lei

RE2C_FILES += \
    AccountParser.cpp.re

re2c.name = RE2C
re2c.output  = ${QMAKE_FILE_BASE}
re2c.variable_out = SOURCES
re2c.commands = re2c -cfo ${QMAKE_FILE_OUT} ${QMAKE_FILE_NAME}
re2c.input = RE2C_FILES
re2c.dependency_type = TYPE_C
QMAKE_EXTRA_COMPILERS += re2c
