#!/usr/bin/perl
################################################################################
# Module:  FizzBuzz.pl
#
# Description:  Demonstration script of finding the divizable integers of an
#    iteration from 1 to 100:
#    - By 3, print "Fizz"
#    - By 5, print "Buzz"
#    - By both 3 & 5, print "FizzBuzz"
#    - Not divizable by either, print original number
#
# Parameters:  NA
#
# Usage:       ./FizzBuzz.pl
#
# Returns:     NA
#
# Changes:
#
# Date        Name                 Description
# ----------  -------------------  ---------------------------------------------
# 03/03/2014  Mikael Sikora        Initial Release
################################################################################
use strict;
use warnings;

#-------------------------------------------------------------------------------
# Initialize variables
#-------------------------------------------------------------------------------

my $i = 0;

#-------------------------------------------------------------------------------
# First, run through the numbers
#-------------------------------------------------------------------------------
for ($i=1; $i <= 100; $i++) {
   print "$i, ";
}

#-------------------------------------------------------------------------------
# Second, apply the tests
#-------------------------------------------------------------------------------
print "\n";
print "---\n";

foreach my $i (1..100) {
    if ((( $i / 3) =~ m/^\d+$/) && (($i / 5) =~ m/^\d+$/)) {
        print "FizzBuzz, ";
    }
    elsif (( $i / 3) =~ m/^\d+$/) {
        print "Fizz, ";
    }
    elsif (($i / 5) =~ m/^\d+$/) {
        print "Buzz, ";
    }
    else {
        print "$i, ";
    }
}
print "\n";