###############################################################################
#
# Strength script
#
# created by Jens M Hebisch
#
# Version 0.2
# Now allows more than one case
#
# This script is intended to compare values in standard cfast rpt files.
# The number of elements can be different between the two files.
# An Envelope will be created. Comparison will be done on individual componets
# as well as on shear
#
# use: perl RPT_Compare_CFAST_els.pl old.rpt new.rpt [groups.ses]
#
# old.rpt:
# single column rpt file with the original/baseline data
# 
# new.rpt:
# single column rpt file with the new data
#
# groups.ses:
# optional file containing groups. If provided, a list of groups which have
# seen load increases will be output
#
# outputs:
# ElmWithIncrease.ses: A session file containing a group of elements with 
# load increases
# IncreasesOnly.txt: Only data for elements with increases in load are reported
# GroupsWithIncrease.log: Only when groups.ses is supplied. Contains all groups
# that have elements with increased loads
# PercentageChange.log: file containing the percentage increase for each 
# element
#
###############################################################################
use warnings;
use strict;

sub readRPT {
	my %rptResults;
	my $rpt = $_[0];
	open(RPT, "<", $rpt);
	while(<RPT>){
		if(m/^\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)(\s*)$/){
			my $EID = $1;
			my $x = $2;
			my $y = $3;
			my $z = $4;
			unless($rptResults{$EID}){
				#[min, max, min, max, min, max, shear max]
				$rptResults{$EID} = [0, 0, 0, 0, 0, 0, 0];
			}
			if($rptResults{$EID}[0] > $x){
				$rptResults{$EID}[0] = $x;
			}
			if($rptResults{$EID}[1] < $x){
				$rptResults{$EID}[1] = $x;
			}
			if($rptResults{$EID}[2] > $y){
				$rptResults{$EID}[2] = $y;
			}
			if($rptResults{$EID}[3] < $y){
				$rptResults{$EID}[3] = $y;
			}
			if($rptResults{$EID}[4] > $z){
				$rptResults{$EID}[4] = $z;
			}
			if($rptResults{$EID}[5] < $z){
				$rptResults{$EID}[5] = $z;
			}
			if($rptResults{$EID}[6] < ($y**2 + $z**2)**0.5){
				$rptResults{$EID}[6] = ($y**2 + $z**2)**0.5;
			}
		}
	}
	close(RPT);
	return %rptResults;
}

my %elements;
sub processCommand{
	my @lines = @_;
	my $command;
	foreach my $line (@lines){
		$command = $command.$line;
	}
	$command =~ s/\"\"//g;
	$command =~ m/\"(.*)\",\s*\"(.*)\"/;
	my $GroupName = $1;
	my $list = $2;
	my @parts = split(" ",$list);
	my $process = 0;
	my @EIDS;
	foreach my $part (@parts){
		if($part =~ m/^([a-z]*)$/i){
			if($part eq "Element"){
				$process = 1;
			}
			else{
				$process = 0;
			}
		}
		elsif($process){
			if($part =~ m/(\d+):(\d+):(\d+)/){
				my $start = $1;
				my $end = $2;
				my $incr = $3;
				for(my $n = $start; $n <= $end; $n = $n + $incr){
					$elements{$n} = $GroupName;
				}
			}
			elsif($part =~ m/(\d+):(\d+)/){
				my $start = $1;
				my $end = $2;
				for(my $n = $start; $n <= $end; $n++){
					$elements{$n} = $GroupName;
				}
			}
			elsif($part =~ m/(\d+)/){
				$elements{$1} = $GroupName;
			}
		}
	}
}

sub readGroupSes{
	my @lines = ();
	open(SES, "<", $_[0]);
	while(<SES>){
		my $line = $_;
		$line =~ s/\@//g;
		$line =~ s/ \/\/ //g;
		$line =~ s/\r\n//g;
		chomp($line);
			if($line =~ m/^\$/ or $line =~ m/^\w/){
			if(@lines){
				my $com =processCommand(@lines);
				@lines = ();
			}
			if($line =~ m/ga_group_entity_add/){
				push(@lines,$line);
			}
		}
		elsif(@lines){
			push(@lines,$line);
		}
	}
	if(@lines){
		my $com =processCommand(@lines);
	}
	close(SES);
}

#process inputs
my @inputs = @ARGV;
my $groupSes = 0;
if (@inputs + 0 > 2){
	$groupSes = $inputs[2];
}
my $oldRpt = $inputs[0];
my $newRpt = $inputs[1];
#process session file if exists
# output in %elements
if($groupSes){
	readGroupSes($groupSes)
}

my %old = readRPT($oldRpt);
my %new = readRPT($newRpt);

my %IncreaseGroups;
my %IncreaseElm;

sub percentageChange{
	my $old = $_[0];
	my $new = $_[1];
	my $percChange;
	if($old == 0){
		if($new == 0){
			$percChange = 0;
		}
		else{
			$percChange = 999;
		}
	}
	else{
		$percChange = ($new - $old) / $old * 100;
	}
	return $percChange;
}

# updates required from this point onwards
my @EIDs = sort({$a <=> $b} keys(%old));
open(OPT, ">", "PercentageChange.els");
print OPT "EnvelopeComparison\n";
print OPT "    7\n";
print OPT "Scalar\n";
print OPT "Value\n";
open(INCR, ">", "IncreasesOnly.txt");
print INCR "Component\tEID\told value\t new value\tpercentage Change\n";
foreach my $EID (@EIDs){
	if($new{$EID}){
		my @new = @{$new{$EID}};
		my @old = @{$old{$EID}};
		my $n = 0;
		print OPT $EID."\n";
		foreach($n = 0; $n < (@new + 0); $n++){
			my $percChange = percentageChange($old[$n], $new[$n]);
			$percChange = $percChange;
			if($percChange > 0){
				$IncreaseElm{$EID} = 1;
				if($groupSes){
					if($elements{$EID}){
						$IncreaseGroups{$elements{$EID}} = 1;
					}
				}
				if($n == 6){
					print INCR "Shear";
				}
				elsif($n % 2 == 0){
					print INCR "Minimum ";
				}
				else{
					print INCR "Maximum ";
				}
				if($n < 2){
					print INCR "Fx";
				}
				elsif($n < 4){
					print INCR "Fy";
				}
				elsif($n < 6){
					print INCR "Fz";
				}
				print INCR "\t".$EID."\t".$old[$n]."\t".$new[$n]."\t".$percChange."\n";
				printf OPT <%.7e>, $percChange;
			}
			else{
				if($percChange == 0){
					printf OPT <%.7e>, $percChange;
				}
				else{
					printf OPT <%.6e>, $percChange;
				}
			}
		}
		print OPT "\n";
	}
}
close(OPT);
close(INCR);
if ($groupSes){
	my @groups = sort(keys(%IncreaseGroups));
	open(OPT, ">", "GroupsWithIncrease.log");
	foreach my $group (@groups){
		print OPT $group."\n";
	}
}
close(OPT);
open(IELM, ">", "ElmWithIncrease.ses");
print IELM "sys_poll_option( 2 )\n";
@EIDs = sort({$a <=> $b} keys(%IncreaseElm));
print IELM "ga_group_create( \"Increased Elements\" )\n";
print IELM "ga_group_entity_add( \"Increased Elements\",  \@\n";
print IELM "\" Element ";
foreach my $EID (@EIDs){
	print IELM "\" \/\/ \@\n\"$EID ";
}
print IELM "\" )\n";
print IELM "sys_poll_option( 0 )\n";
close(IELM);