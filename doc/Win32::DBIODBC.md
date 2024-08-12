# NAME

Win32::DBIODBC - Win32::ODBC emulation layer for the DBI

# SYNOPSIS

    use Win32::DBIODBC;     # instead of use Win32::ODBC

# DESCRIPTION

This is a _very_ basic _very_ alpha quality Win32::ODBC emulation
for the DBI. To use it just replace

        use Win32::ODBC;

in your scripts with

        use Win32::DBIODBC;

or, while experimenting, you can pre-load this module without changing your
scripts by doing

        perl -MWin32::DBIODBC your_script_name

# TO DO

Error handling is virtually non-existent.

# AUTHOR

Tom Horen <tho@melexis.com>