#!/bin/sh

umask 002;

export FCID=$1;
export Pool=$2;
export Barcodes=$3;

if [ -z "${FCID}" ];
then echo "Error: Flowcell ID not specified";
exit 1;
fi;

if [ -z "${Pool}" ];
then export Pool=`pwd -P | rev | cut -f1 -d "/" | rev`;
fi;

if [ -z "${Barcodes}" ];
then export Barcodes=`readlink -e Barcodes.txt`;
fi;

echo `pwd`

#Run the make fastq portion of the pipeline.
export BCL=`ssh -l ILMpipe cmmr-seqapp01 "ls /data/ILM_DropBox/ | grep ${FCID}"`;
echo "rsync -aL ILMpipe@cmmr-seqapp01-10g:/data/ILM_DropBox/${BCL} \${TMPDIR};
${GITREPO}/16S/MakeFastqsFromBCLs.pl --BclDir \${TMPDIR}/${BCL} --sampleSheet ${Barcodes} --ProjectName ${Pool} --threads 40;
${GITREPO}/16S/ExtraBarcodeFinder.sh;" | qsub -l ncpus=20 -q batch -N ${Pool}.MakeFastqs -d `pwd -P` -o Logs/ -e Logs/ -V > jobIDs.temp;
while [ `qstat | grep -f jobIDs.temp | wc -l` -gt 0 ];
do sleep 100;
done;
rm jobIDs.temp;

#Check for any Golay barcodes that should not exist according to the sample sheet.  If they are found, terminate.
if [ `cat AdditionalGolayFoundBarcodes.txt | wc -l` -gt 0 ];
then echo -e "${Pool} had Golay barcodes not-accounted for in the sample sheet!\n\n`cat HiddenBarcodeStats.txt`" | mail -a AdditionalGolayFoundBarcodes.txt -s "${Pool} Golay Barcode Error" ${USER}@bcm.edu,mcross@bcm.edu,Nadim.Ajami@bcm.edu;
exit 1;
fi;

#Create the Controls and run the full pool for stats.
~gesell/Programs/gitHub/16S/PoolLink.sh C CMMR_Controls `echo ${Pool} | sed -e "s:Pool::g"` CMMR `echo "${Pool}.16SV4"` &
echo "${Pool} has finished MakeFastQs and can be separated by project." | mail -s "${Pool} has finished MakeFQs" ${USER}@bcm.edu &
echo "${GITREPO}/16S/fullPipelineSplit.sh `pwd -P`/${Pool}WorkDir/Reads 40" | qsub -l ncpus=20 -q batch -N ${Pool}.Process -d `pwd -P` -o Logs/ -e Logs/ -V &
wait;

exit 0;
