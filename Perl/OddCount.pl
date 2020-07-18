#!/usr/bin/perl
################################################################################
# Module:  OddCount.pl
#
# Description:  Demonstration script of finding the odd number of occurances of
#   elements in an array
#
# Parameters:  NA
#
# Usage:  ./OddCount.pl
#
# Returns:  NA
#
# Changes
#
# Date       Name                 Description
# ---------  -------------------  ----------------------------------------------
# 11/2/2012  Mikael Sikora        Initial Release
# 11/2/2012  Mikael Sikora        Converted to use subroutines
################################################################################
use strict;

#-------------------------------------------------------------------------------
# Initialize variables
#-------------------------------------------------------------------------------
my @array1 = (2, 2, 3, 4, 3, 5, 5);
my @array2 = (2, 2, 2, 3, 3, 6, 6);

my @array3 = {
    a => [2, 2, 3, 4, 3, 5, 5],
    b => [2, 2, 2, 3, 3, 6, 6]
};

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

# foreach my $array4 (@array3) {
#    print "=======\n";
#    print "Array ?\n";
#    print "=======\n";
#    print "\n";
#    process_array ($array4);
#    print "=======\n";
#    print "\n";
# }

print "=======\n";
print "Array 1\n";
print "=======\n";
print "\n";
process_array (@array1);
print "=======\n";
print "\n";

print "=======\n";
print "Array 2\n";
print "=======\n";
print "\n";
process_array (@array2);

################################################################################
#
# Subroutine:  process_array
#
# Description:  Process the array
#
# Parameters:  Array
#
# Returns:  NA
#
################################################################################
sub process_array {
    my @array = @_;
    my %hash;
    
    print_array (@array);
    %hash = count_unique (@array);
    print_results (\%hash);
}

################################################################################
#
# Subroutine:  print_array
#
# Description:  Print the contents of the array
#
# Parameters:  Array
#
# Returns:  NA
#
################################################################################
sub print_array {
    my @array = @_;
    
    print "Array of Numbers\n";
    print "----------------\n";
    print "@array\n";
    print "\n";
}

################################################################################
#
# Subroutine:  count_unique
#
# Description:  Create hash of array elements and how many times same value 
#   occurs in array
#
# Parameters:  Array
#
# Returns:  Hash
#
################################################################################
sub count_unique {
    my @array = @_;
    my %hash;
    
    foreach my $number (@array) {
        $hash{$number}++;
    }
    
    return %hash;
}

################################################################################
#
# Subroutine:  print_results
#
# Description:  Print out the unique elements and how many times same value 
#   occurs is array
#
# Parameters:  Array
#
# Returns:  NA
#
################################################################################
sub print_results {
    my %hash = %{shift()};
    
    print "Key = Unique Number, Val = # of Occurances\n";
    print "------------------------------------------\n";
    while ( my ($key, $val) = each %hash) {
        print "Key = $key, Val = $val\n";
    }
    print "\n";

    # Determine odd number of occurances and print it out
    print "Odd occurances of duplicate elements\n";
    print "------------------------------------\n";
    while ( my ($key, $val) = each %hash) {
        if ($val % 2 == 1) {
            print "Array Value = $key, # of Occurances = $val\n";
        }
    }
}

exit;