#!/bin/sh

export READSDIR=$1;
export THREADS=$2;
CURRWORKDIR=`pwd`;

#If no thread count was passed, used all available threads on the cluster
if [ -z "${THREADS}" ];
then export THREADS=`grep -c ^processor /proc/cpuinfo`;
fi

#If no reads directory was passed, sets it to the current directory
if [ -z "${READSDIR}" ];
then export READSDIR=".";
fi

#Verify the existence of the temporary directory
if [ -d $(readlink -e ${TMPDIR}) ];
then echo "Temporary Directory: ${TMPDIR}";
else echo "Temporary Directory does not exist";
fi

#go into Reads dir
export READSDIR=`readlink -e ${READSDIR}`;
cd ${READSDIR};
export PROJECTID=`basename $(readlink -e ${READSDIR}/..) | sed 's/WorkDir//g'`;
echo "Current Reads Directory: ${READSDIR}";
echo "Current Project ID: ${PROJECTID}";

cat ${READSDIR}/../../${PROJECTID}.barcodeCounts.txt | grep -f ${READSDIR}/../SampleList > ${TMPDIR}/${PROJECTID}.barcodeCounts.txt &
wait;
mkdir -p ${READSDIR}/../../Deliverables

mkdir ${TMPDIR}/uparseStrict;
usearch70 -derep_fulllength ${READSDIR}/../split_libraries/Strict.seqs.fna -output ${TMPDIR}/uparseStrict/derep.fna -sizeout -uc ${TMPDIR}/uparseStrict/derep.uc 2>&1;
usearch70 -sortbysize ${TMPDIR}/uparseStrict/derep.fna -output ${TMPDIR}/uparseStrict/sorted.fa -minsize 2;
cp ${TMPDIR}/uparseStrict/sorted.fa ${TMPDIR}/uparseStrict/temp.fa;
for i in {0.4,0.8,1.2,1.6,2.0,2.4,2.8,3.2};
do usearch70 -cluster_otus ${TMPDIR}/uparseStrict/temp.fa -otus ${TMPDIR}/uparseStrict/temp1.fa -otu_radius_pct $i -uc ${TMPDIR}/uparseStrict/cluster_$i.uc -fastaout ${TMPDIR}/uparseStrict/clustering.$i.fasta.out;
cat ${TMPDIR}/uparseStrict/clustering.$i.fasta.out | grep "^>" | grep chimera | sed "s/^>//g" | sed -re "s/;n=.*up=/\t/g" | sed "s/;$//g" | tee -a ${TMPDIR}/uparseStrict/chimeras.txt > ${TMPDIR}/uparseStrict/chimeras.$i.txt;
cat ${TMPDIR}/uparseStrict/clustering.$i.fasta.out | grep "^>" > ${TMPDIR}/uparseStrict/uparseStrictref.decisions.$i.txt;
rm ${TMPDIR}/uparseStrict/clustering.$i.fasta.out;
mv ${TMPDIR}/uparseStrict/temp1.fa ${TMPDIR}/uparseStrict/temp.fa;
done;
mv ${TMPDIR}/uparseStrict/temp.fa ${TMPDIR}/uparseStrict/otus1.fa;
usearch70 -uchime_ref ${TMPDIR}/uparseStrict/otus1.fa -db ${GOLD} -strand plus -uchimeout ${TMPDIR}/uparseStrict/uchimeref.uc;
cat ${TMPDIR}/uparseStrict/uchimeref.uc | cut -f2,18 | grep -v "Y$" | cut -f1 | ${GITREPO}/Miscellaneous/getSeq ${TMPDIR}/uparseStrict/otus1.fa > ${TMPDIR}/uparseStrict/otus.fa;
usearch70 -usearch_global ${TMPDIR}/uparseStrict/otus.fa -db ${SILVA}/silva_V4.udb -id .968 -strand plus -threads ${THREADS} -uc ${TMPDIR}/uparseStrict/otus2taxa.uc -maxaccepts 0 -maxrejects 0;
cat ${TMPDIR}/uparseStrict/derep.fna | grep -A1 "size=1;" | cut -f2 -d ">" | ${GITREPO}/Miscellaneous/getSeq ${TMPDIR}/uparseStrict/derep.fna > ${TMPDIR}/uparseStrict/singletons.fna;
usearch70 -usearch_global ${TMPDIR}/uparseStrict/singletons.fna -db ${TMPDIR}/uparseStrict/sorted.fa -id .99 -uc ${TMPDIR}/uparseStrict/singletons2otus.uc -strand plus -threads ${THREADS} -maxaccepts 32 -maxrejects 128 -minqt 1 -leftjust -rightjust -wordlength 12;
cd ${TMPDIR}/uparseStrict;
${GITREPO}/Miscellaneous/resolveIterativeUparse.pl ${TMPDIR}/uparseStrict/cluster_*.uc ${TMPDIR}/uparseStrict/singletons2otus.uc ${TMPDIR}/uparseStrict/otus2taxa.uc --derep ${TMPDIR}/uparseStrict/derep.uc --chimeras ${TMPDIR}/uparseStrict/chimeras.txt --uchime ${TMPDIR}/uparseStrict/uchimeref.uc --taxonomy ${SILVA}/silva.map;
biom summarize-table -i ${TMPDIR}/uparseStrict/otu_table.biom -o ${TMPDIR}/uparseStrict/Stats.StrictMerge.otu_table.txt;
if [ $? -eq 0 ];
then echo "biom Strict Stats run successful";
else echo "biom Strict Stats run failed";
fi;
var=$(expr `cat ${TMPDIR}/uparseStrict/Stats.StrictMerge.otu_table.txt | grep -n "Counts/sample detail" | cut -f1 -d ":"` + 1);
if [ $var -eq 1 ];
then echo "No start-line found, terminating";
fi;
cat ${TMPDIR}/uparseStrict/Stats.StrictMerge.otu_table.txt | tail -n +$var | sed "s/^ //g" | sed -re "s/: /\t/g" | sed "s/\.0$//g" > ${READSDIR}/../Stats.StrictMerge.MappedReads.txt;
cat ${READSDIR}/../split_libraries/Strict.seqs.fna | grep "^>" | cut -f1 -d "_" | cut -f2 -d ">" | sort | uniq -c > ${READSDIR}/../Stats.StrictMerge.MergedReads.txt;
perl ${GITREPO}/16S/StatsComparisonMergedVsMapped.pl ${TMPDIR}/${PROJECTID}.barcodeCounts.txt ${READSDIR}/../Stats.StrictMerge.MergedReads.txt ${READSDIR}/../Stats.StrictMerge.MappedReads.txt > ${READSDIR}/../Stats.StrictMerge.Combined.txt;
tar -cvjf ${READSDIR}/../uparseStrict.tar.bz2 -C ${TMPDIR} uparseStrict;
cp ${TMPDIR}/uparseStrict/otu_table.biom ${READSDIR}/../../Deliverables/OTU_Table.biom; 
cp ${READSDIR}/../Stats.StrictMerge.Combined.txt ${READSDIR}/../../Deliverables/Read_QC.txt;
exit 0;
