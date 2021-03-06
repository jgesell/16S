#!/bin/bash

export inputFiles=$1;
#Input is a list of directories that need to be merged.
export outputDirectory=$2;


#Check to see if the merge directory already exists
if [ ! -f $outputDirectory ];
then mkdir $outputDirectory;
echo "Made output directory at $outputDirectory";
fi

export outputDirectory=`readlink -e \`echo $outputDirectory\``;
export outname=`echo $outputDirectory | rev | cut -f1 -d "/" | rev`

#Makes the directory structure for the merged directory
mkdir ${outputDirectory}/Logs;
mkdir -p ${outputDirectory}/${outname}Reads/Project_${outname};
mkdir -p ${outputDirectory}/${outname}WorkDir/Reads;
mkdir -p ${outputDirectory}/${outname}Barcodes/Project_${outname}/Sample_${outname};
total=0;

#Cycles thru each input directory and links/merges the needed read files for each sample
for i in `cat $inputFiles`;
do input=`readlink -e ${i}`;
counter=0;
echo "Adding pool ${input} to the merged set"

#Verify the existence of the barcodeCounts.txt file
if [ -z ${input}/*.barcodeCounts.txt ];
then for j in `cat ${input}/*WorkDir/SampleList`;
do count=`bzcat ${input}/*WorkDir/Reads/${j}.1.fq | wc -l`;
count=$[count / 4];
echo -e "${j}\t${count}";
done >> ${outputDirectory}/${outname}.barcodeCounts.txt;
else name=`echo ${input} | rev | cut -f1 -d "/" | rev`;
cat ${input}/*.barcodeCounts.txt | grep -f ${input}/*WorkDir/SampleList | sed -e "s:\t:.${name}\t:g" >> ${outputDirectory}/${outname}.barcodeCounts.txt;
fi;

#Create the links to the reads
for j in `find ${input}/*Reads/Project_*/Sample_* -maxdepth 0  | grep -f ${input}/*WorkDir/SampleList`;
do count=`echo $input | rev | cut -f1 -d "/" | rev`
counter=`echo $((counter + 1))`;
total=`echo $((total + 1))`;
name=`echo ${j} | rev | cut -f1 -d "/" | rev`;
name2=`echo ${name}.${count}`;
mkdir ${outputDirectory}/${outname}Reads/Project_${outname}/${name2};
for file in `ls ${j}`;
do fileName=`echo ${file} | sed "s:\`echo ${name} | cut -f2-100 -d '_'\`:\`echo ${name2} | cut -f2-100 -d '_'\`:g"`;
ln -s ${j}/${file} ${outputDirectory}/${outname}Reads/Project_${outname}/${name2}/${fileName};
done;
echo ${name2} | sed 's:Sample_::g' >> ${outputDirectory}/${outname}WorkDir/SampleList;
done;

#Cat together the required stats files to get accurate read statistics
if [ -z ${input}/samplesheet.*.csv ];
then for j in `cat ${input}/*WorkDir/SampleSheet`;
do echo -e "000000000-XXXXX,1,${i},,NNNNNNNNNNNN,,N,1,JRG,`echo ${input} | rev | cut -f1,2 -d '/' | rev | tr -s '/' '.'`" >> ${outputDirectory}/samplesheet.${outname}.csv;
done;
else for j in `find ${input}/samplesheet.*.csv`;
do for k in `cat ${j}`;
do name=`echo ${k} | cut -f3 -d ","`;
name2=`echo ${name}.${count}`;
echo ${k} | sed "s:${name}:${name2}:g" >> ${outputDirectory}/samplesheet.${outname}.csv
done;
done;
fi;
cat ${input}/sampleSheet.notDemultiplexed.*.csv >> ${outputDirectory}/sampleSheet.notDemultiplexed.${outname}.csv;
count=`echo $input | rev | cut -f1 -d "/" | rev`;
echo "Total samples from pool ${input} = ${counter}";
if [ "${counter}" -eq 0 ];
then echo "Error: no samples found for pool ${input}\!";
exit 1;
fi;
done;

#Creates simlinks to the read files in the working directory
for j in `ls ${outputDirectory}/${outname}Reads/Project_${outname}`;
do name=`echo $j | rev | cut -f1 -d "/" | rev | sed 's:Sample_::g'`;
for seq in `ls ${outputDirectory}/${outname}Reads/Project_${outname}/${j} | grep "bz2" | tr "+" "A"`
do link=`echo $seq | sed -r 's:_[ACGNT]+_L001_R1_001.fastq:@.1.fq:g' | sed -r 's:_[ACGNT]+_L001_R2_001.fastq:@.2.fq:g'`;
temp=`echo $link | cut -f1 -d "@"`
link=`echo $link | sed "s:${temp}:${name}:g" | sed 's:@::g'`;
ln -s ${outputDirectory}/${outname}Reads/Project_${outname}/${j}/${seq} ${outputDirectory}/${outname}WorkDir/Reads/${link};
done;
done;
cd ${outputDirectory}/${outname}WorkDir/Reads;
echo "Total samples found: ${total}";
echo ${GITREPO}/16S/fullPipelineSplit.sh | qsub -l ncpus=20 -q batch -N ${outname}.Process -d `pwd -P` -V -o ${outputDirectory}/Logs/ -e ${outputDirectory}/Logs/;
exit 0;
