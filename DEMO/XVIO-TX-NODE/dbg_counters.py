#!/usr/bin/python2

import sys
import string
import subprocess
import tempfile
import getopt
import time

def usage():
    print "usage: {} [options]".format(sys.argv[0])
    print
    print "Where [options] are:"
    print "  -a|--absolute              Display the absolute values of the counters. This is the"
    print "                             default behaviour."
    print "  -d|--delta DELAY           Display counter delta's over the DELAY period in seconds."
    print "  -z|--non-zero              Display non-zero counters only."
    print "                             If the delta option has been selected, counters with zero deltas"
    print "                             and non-zero absolute values will still be displayed."
    print "  -c|--clear                 Clear debug counters after reading them."
    print "  -C|--clear-all             Clear port statistic counters and debug counters without reading."
    print "  -h|--help                  Display this usage message."
    print

##################
# Option Parsing #
##################

try:
    opts, args = getopt.getopt(sys.argv[1:], "ad:zcCh", ["absolute", "delta=", "non-zero", "clear", "clear-all", "help"])
except getopt.GetoptError as err:
    print str(err)
    usage()
    sys.exit(2)

absolute = True
deltaPeriod = 0
nonZero = False
clear = False
clearAll = False

for opt, arg in opts:
    if opt in ("-a", "--absolute"):
        absolute = True
        deltaPeriod = 0
    elif opt in ("-d", "--delta"):
        absolute = False
        deltaPeriod = int(arg, 0)
    elif opt in ("-z", "--non-zero"):
        nonZero = True
    elif opt in ("-c", "--clear"):
        clear = True
    elif opt in ("-C", "--clear-all"):
        clearAll = True
    elif opt in ("-h", "--help"):
        usage()
        sys.exit()
    else:
        assert False, "unhandled option"

def clearCounters():
    symFile = tempfile.TemporaryFile()
    subprocess.call(["/opt/netronome/bin/nfp-rtsym", "-L"], stdout=symFile)

    symFile.seek(0)
    for line in symFile:
        values = line.split()
        if len(values) > 0 and "pkt_counters_base" in values[0]:
            subprocess.call(["/opt/netronome/bin/nfp-rtsym", "-l", values[3], values[0], "0"])

def clearPortStats():
    #VF rate limiter stats. Clear this "surgically" because this mem struct contains other info, not just stats
    symFile = tempfile.TemporaryFile()
    subprocess.call(["/opt/netronome/bin/nfp-rtsym", "-L"], stdout=symFile)
    symFile.seek(0)
    length_vf_rl_mem = 0 #VF Rate limiter mem
    length_vf_rl_ovf = 0 #VF Rate limiter overflow mem
    length_mac_stats = 0 # _mac_stats
    length_mac_stats_head_drop_accum = 0 # _mac_stats_head_drop_accum
    for line in symFile:
        values = line.split()
        if len(values) > 0 and "VF_RATE_LIMITER_MEM" in values[0]:
            length_vf_rl_mem = int(values[3], 16)

        if len(values) > 0 and "VF_RATE_LIMITER_OVF" in values[0]:
            length_vf_rl_ovf = int(values[3], 16)

        if len(values) > 0 and "_mac_stats" == values[0]:
            length_mac_stats = int(values[3], 16)

        if len(values) > 0 and "_mac_stats_head_drop_accum" == values[0]:
            length_mac_stats_head_drop_accum = int(values[3], 16)

        if (length_vf_rl_mem > 0) & (length_vf_rl_ovf > 0) & (length_mac_stats > 0) & (length_mac_stats_head_drop_accum > 0):
            break
    addr = 32
    while (addr < (length_vf_rl_mem - 32)) :
        len_str="--len=%s"%(hex(24))
        sym_str="VF_RATE_LIMITER_MEM:%s"%(hex(addr))
        subprocess.check_output(["/opt/netronome/bin/nfp-rtsym", len_str, sym_str, "0"])
        addr = addr + 64

    len_str="--len=%s"%hex(length_mac_stats)
    subprocess.check_output(["/opt/netronome/bin/nfp-rtsym", len_str, "_mac_stats", "0"])

    len_str="--len=%s"%hex(length_mac_stats_head_drop_accum)
    subprocess.check_output(["/opt/netronome/bin/nfp-rtsym", len_str, "_mac_stats_head_drop_accum", "0"])

    subprocess.check_output(["/opt/netronome/bin/nfp-rtsym", "--len=0x4000", "LOGICAL_PORT_VLAN_STATS_TABLE", "0"])

    len_str="--len=%s"%hex(length_vf_rl_ovf)
    subprocess.check_output(["/opt/netronome/bin/nfp-rtsym", len_str, "VF_RATE_LIMITER_OVF", "0"])

    subprocess.check_output(["/opt/netronome/bin/nfp-rtsym", "--len=4096", "_nfd_stats_in_recv", "0"])
    subprocess.check_output(["/opt/netronome/bin/nfp-rtsym", "--len=4096", "_nfd_stats_out_drop", "0"])
    subprocess.check_output(["/opt/netronome/bin/nfp-rtsym", "--len=4096", "_nfd_stats_out_sent", "0"])
    subprocess.check_output(["/opt/netronome/bin/nfp-rtsym", "--len=4096", "_nfd_stats_out_sent", "0"])
    subprocess.check_output(["cat", "/sys/module/nfp_fallback/control/clear_fallback_counters"])

def extractCounters():
    processedCounters = []
    globalCountersRaw = []
    pcie_rx = 0
    pcie_rx_all = -1
    cmsg_rx = 0

    symFile = tempfile.TemporaryFile()
    subprocess.call(["/opt/netronome/bin/nfp-rtsym", "-L"], stdout=symFile)

    symFile.seek(0)
    for line in symFile:
        values = line.split()
        if len(values) > 0 and "pkt_counters_base" in values[0]:

            counterParameterList=[]
            dataList=[]
            counterParameterList.append(values)

            dataFile=tempfile.TemporaryFile()
            subprocess.call(["/opt/netronome/bin/nfp-rtsym", "-v", values[0]], stdout=dataFile)

            dataFile.seek(0)
            for line in dataFile:
                dataValues=line.split()
                if len(dataValues) > 0:
                    dataValues[0] = dataValues[0].replace(':', '')
                    dataList.append(dataValues)
            dataFile.close()
            counterParameterList.append(dataList)

            globalCountersRaw.append(counterParameterList)


    def searchForCounterParent(name, mem, base, size):
        for blockRecord in globalCountersRaw:
            blockMem = blockRecord[0][1]
            blockBase = int(blockRecord[0][2], 0)
            blockSize = int(blockRecord[0][3], 0)
            if blockMem == mem and blockBase <= base and (blockBase+blockSize) >= (base+size):
                offset = base - blockBase
                for dataRecord in blockRecord[1]:
                    dataBase = int(dataRecord[0], 0)
                    if dataBase <= offset and (dataBase + 0xf) > offset:
                        if size != 8:
                            print >>sys.stderr, "Counter is not 8 bytes wide - misalignment detected!! Values may be wrong"

                        dataOffset = offset - dataBase
                        if dataOffset == 0:
                            value = (int(dataRecord[2], 0)<<32) + int(dataRecord[1], 0)
                        else:
                            value = (int(dataRecord[4], 0)<<32) + int(dataRecord[3], 0)
                return value

        dataRecord = subprocess.check_output(["/opt/netronome/bin/nfp-rtsym", "{}__cntr__".format(name)]).split()
        if (len(dataRecord) == 3):
            value = (int(dataRecord[2], 0)<<32) + int(dataRecord[1], 0)
            return value
        else:
            print "UNABLE to find match for {}".format(name)
            return 0

    symFile.seek(0)
    for line in symFile:
        values = line.split()
        if len(values) > 0 and "__cntr__" in values[0]:
            counterName = values[0].replace('__cntr__', '')
            value = searchForCounterParent(counterName, values[1], int(values[2], 0), int(values[3], 0))
            if(counterName == "pcie_rx_all") :
                pcie_rx_all = value
            if(counterName == "cmsg_rx") :
                cmsg_rx = value
            processedCounters.append((counterName, value))

    if (pcie_rx_all >= 0) :
        pcie_rx = pcie_rx_all - cmsg_rx
        processedCounters.append(("pcie_rx", pcie_rx))

    symFile.close()
    return processedCounters

#################
# Main function #
#################

timestamp = time.time()
counters = extractCounters()
counters = sorted(counters, key=lambda counter: counter[1], reverse=True)

if clearAll:
    clearCounters()
    clearPortStats()

elif absolute:
    for counter in counters:
        if not(nonZero) or (nonZero and counter[1] > 0):
            print "{:30}: {}".format(counter[0], counter[1])

elif deltaPeriod != 0:
    diff = time.time() - timestamp
    while diff < deltaPeriod:
        # spin
        diff = time.time() - timestamp

    nextCounters = extractCounters()
    nextCounters = sorted(nextCounters, key=lambda nextCounter: nextCounter[1], reverse=True)


    for idx, counter in enumerate(counters):
        if not(nonZero) or (nonZero and counter[1] > 0):
            print "{:30}: {}".format(counter[0], (nextCounters[idx][1] - counter[1]))

else:
    # This should never happen
    print >>sys.stderr, "Neither absolute nor delta options were selected!"

if clear:
    clearCounters()
