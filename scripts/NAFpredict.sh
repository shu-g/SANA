#!/bin/sh
USAGE="$0 -[p|v] seqSim go1 go2 tax1 tax2 NAFthresh col1 col2 [Resnik.files]
where:
seqSim is the file with sequence similarities used to eliminate predictions possible to predict by sequence
go1 is the source gene2go file which makes predictions which are searched in go2
tax1 and tax2 are the predictor and predictee taxonomic IDs (eg 10090 for mouse, 9606 for human)
NAFthresh is the lower predictive bound, and has a leading dash if you want to predict in the opposite direction
    to the directory names (eg 0 to predict MM->HS or -0 for MM<-HS)
col1,col2 are the columns in the files where protein names are found
files contain at laest 2 columns with aligned protein pairs, including duplicates and NO count
    (we will compute NAF in the script) [no files means you're sending to stdin]
-p means list all predictions (turns off counting)
-v means list the validated  predictions (turns off counting)
"

die(){ echo "$USAGE">&2; echo "$@" >&2; exit 1
}

LIST_PRED=false
LIST_VAL=false
case "$1" in
-p) LIST_PRED=true;shift;;
-v) LIST_VAL=true;shift;;
-*) die "unknown option '$1'";;
esac

[ $# -ge 8 ] || die "expecting at least 8 args, not $#"
seqSim="$1"
go1="$2"
go2="$3"
t1=$4
t2=$5
NAFthresh=$6
c1=$7
c2=$8
shift 8
[ -f "$go1" ] || die "can't find gene2go file '$go1'"
[ -f "$go2" ] || die "can't find gene2go file '$go2'"

TMPDIR=/tmp/GOpredict.$$
trap "/bin/rm -rf $TMPDIR" 0 1 2 3 15
mkdir $TMPDIR
dataDir=`echo "$@" | newlines | sed 's,/[^/]*$,,' | sort -u`
sort "$@" | uniq -c | sort -nr | awk 'BEGIN{t1='$t1';t2='$t2';
	c1=1+'$c1';c2=1+'$c2'; # increment column since "uniq -c" above prepends NAF to the line
    }
    ARGIND==1{seq[$1][$2]=1} # sequence similar pairs
    ARGIND==2&&$1>='$NAFthresh'{u=$c1;;v=$c2;
	if(u in seq && v in seq[u])next; # ignore if sequence similar
	NAF[u][v]=$1
    }
    ARGIND==3{FS="	"; if(/	NOT	/)next} # make FS a tab, and ignore "NOT" lines
    ARGIND==3&&($1==t1||$1==t2){++pGO[$1][$2][$3][$4]; # species, protein, GO, evidence code
	H[$3]=$NF; # hierarchy (BP,MF,CC)
    }
    END{for(p1 in pGO[t1]) # loop over all proteins in species1 that have any GO terms
	if(p1 in NAF) # if we have a predictive NAF value for that protein...
	    for(p2 in NAF[p1]) # loop over all the species2 proteins aligned to p1
		for(g in pGO[t1][p1]) # loop over all the GO terms from protein p1
		    # if protein p2 is not listed at all in the gene2go file...
		    #... or if it is but does not have this particular GO term...
		    if(!(p2 in pGO[t2]) ||!(g in pGO[t2][p2]))
		    # it is a prediction!!! Print out the expected line to find in the later gene2go file:
			for(ec in pGO[t1][p1][g]) # print the evidence codes from p1
			    printf "%d\t%s\t%s\t%s\t%s\n",t2,p2,g,ec,H[g]
    }' "$seqSim" - "$go1" | sort -u | tee $TMPDIR/predictions.allCol |
	cut -f1-3 | # remove evidence code &hier from prediction before search
	sort -u | fgrep -f - "$go2" | fgrep -v '	NOT	' | sort -u > $TMPDIR/validated.allCol
if $LIST_PRED; then cat $TMPDIR/predictions.allCol
elif $LIST_VAL; then cat $TMPDIR/validated.allCol
else
    evCodesPred=`cut -f4 $TMPDIR/predictions.allCol | sort -u`
    evCodesVal=`cut -f4 $TMPDIR/validated.allCol | sort -u`
    hierVal=`cut -f8 $TMPDIR/validated.allCol | sort -u`
    # Shorten GO names for output
    GO1=`echo $go1|sed 's,^.*/go/,,'`
    GO2=`echo $go2|sed 's,^.*/go/,,'`
    for ec in $evCodesPred; do
	pred=`fgrep "	$ec" $TMPDIR/predictions.allCol | cut -f1-3 | sort -u | tee $TMPDIR/pred$ec | wc -l`
	val=`fgrep -f $TMPDIR/pred$ec $TMPDIR/validated.allCol | cut -f1-3 | sort -u | tee $TMPDIR/val$ec | wc -l`
	echo "$ec $pred $val" |
	    awk '$2>0{printf "%10s %3s NAF %3d : %6d pred %5d val prec %5.1f%%\n",
		"'$dataDir'",$1,'$NAFthresh',$2,$3,100*$3/$2}'
    done > $TMPDIR/predECSummary
    for h in $hierVal; do
	pred=`fgrep "	$h" $TMPDIR/predictions.allCol | cut -f1-3 | sort -u | tee $TMPDIR/pred$h | wc -l`
	val=`fgrep -f $TMPDIR/pred$h $TMPDIR/validated.allCol | cut -f1-3 | sort -u | tee $TMPDIR/val$h | wc -l`
	echo "$h $pred $val" |
	    awk '$2>0{printf "%10s %9s NAF %3d : %6d pred %5d val prec %5.1f%%\n",
		"'$dataDir'",$1,'$NAFthresh',$2,$3,100*$3/$2}'
    done > $TMPDIR/predHierSummary
    echo "Predictions by evidence code for $dataDir $GO1 -> $GO2, NAF $NAFthresh"
    lastCol=`awk '{print NF}' $TMPDIR/predECSummary | sort | uniq -c | sort -nr | head -1 | awk '{print $2}'`
    [ "X$lastCol" != X ] && sort -k ${lastCol}gr $TMPDIR/predECSummary
    echo "Predictions by GO hierarchy for $dataDir $GO1 -> $GO2, NAF $NAFthresh"
    lastCol=`awk '{print NF}' $TMPDIR/predHierSummary | sort | uniq -c | sort -nr | head -1 | awk '{print $2}'`
    [ "X$lastCol" != X ] && sort -k ${lastCol}gr $TMPDIR/predHierSummary
fi