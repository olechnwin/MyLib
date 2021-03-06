
#//Antisense
# ---------------------------------------------------------------------------- #
.get_Region_Annotation = function(regs.int, regs.annot, annot , name, merge.by='transcript_id'){

  raf    = dtfindOverlaps(regs.int, regs.annot)
  raf$id = names(regs.annot)[raf$subjectHits]
  raf    = merge(raf, annot, by.x='id', by.y=merge.by)
  setnames(raf, 'id', merge.by)
  ref    = unique(raf[,c('queryHits','gene_id','gene_name'),with=FALSE])
  raf    = raf[,lapply(.SD, function(x)paste(unique(x),collapse=':')),by='queryHits']

  annot.tab = DataFrame(
    ind = (1:length(regs.int) %in% raf$queryHits),
    gene_id = 'None',
    gene_name = 'None')

  annot.tab$gene_id[raf$queryHits]   = raf$gene_id
  annot.tab$gene_name[raf$queryHits] = raf$gene_name
  colnames(annot.tab) = paste(name, colnames(annot.tab), sep='.')
  return(annot.tab)

}


annotate_Antisense = function(
    regs,
    gtf,
    tss.up          = 1000,
    tss.down        = 1000,
    tts.down        = 1000,
    tss.dist.param  = 2000,
    antisense.annot = FALSE){

    library(GenomicRanges)

    if(class(gtf) != 'GRanges' ){
        if(class(gtf) == 'list' && 'gtf' %in% names(gtf)){
            gtf.sel = gtf$gtf
            annot   = gtf$annot
        }else{
            stop('GTF is not in a recognized format')
        }

    }else{
        gtf.sel = gtf
        annot   = as.data.frame(values(gtf.sel))
        annot   = annot[,c('gene_name','gene_id','transcript_id')]
        annot   = unique(data.table(annot))
    }

    genes = unlist(range(split(gtf.sel, gtf.sel$gene_id)))
    trans = unlist(range(split(gtf.sel, gtf.sel$transcript_id)))

    tss = promoters(resize(trans, fix='start', 1), upstream=tss.up, downstream=tss.down)
    tts = promoters(resize(trans, fix='end', 1),   upstream=0, downstream=tts.down)

    regs.tss = resize(regs, width=1, fix='start')
    regs.tss.anti = invertStrand(regs.tss)

    nreg = nchar(length(regs)) + 1
    ids  = paste0('Anti%0',nreg,'d')
    regs$antisense_id = sprintf(ids, 1:length(regs))

    # ------------------------------------------------------------------------ #
    message('Reathrough...')
        regs$readthrough = countOverlaps(regs.tss, tts) > 0

    # ------------------------------------------------------------------------ #
    message('TSS Antisense...')
        ds.tss.anti = .get_Region_Annotation(regs.tss.anti, tss, annot, 'tss_anti')

    # ------------------------------------------------------------------------ #
    message('Gene Body Antisense...')
        ds.gb.anti = .get_Region_Annotation(regs.tss.anti, genes, annot, 'gene_body_anti',
                                        merge.by='gene_id')

    # ------------------------------------------------------------------------ #
    message('TSS Sense...')
        ds.tss = .get_Region_Annotation(regs.tss, tss, annot, 'tss')

    # ------------------------------------------------------------------------ #
    message('Convergent - Divergent ... ')
        regs = Annotate_Divergent_Convergent(
            regs, gtf, antisense.annot, tss.dist.param = tss.dist.param)

    ds.all = cbind(ds.tss.anti, ds.gb.anti, ds.tss)
    values(regs) = cbind(values(regs), ds.all)
    return(regs)

}



# ---------------------------------------------------------------------------- #
Annotate_Divergent_Convergent = function(
    rsa,
    gtf = NULL,
    antisense.annot = FALSE,
    tss.dist.param = 2000
){

    if(is.null(gtf))
        stop('GTF file is not specified')

    library(GenomicRanges)
    message('Preparing annotation ...')
        rsa.tss = resize(rsa, width=1, fix='start')
        rsa.tss.str = invertStrand(rsa.tss)

        gtf.l = subset(gtf, type=='exon')
        gtf.l = unlist(reduce(split(gtf.l, gtf.l$gene_id)))
        sl = seqlevels(gtf.l)
        sl = sl[!str_detect(sl,'HSCHR')]
        sl = sl[!str_detect(sl,'PATCH')]
        sl = sl[!str_detect(sl,'GL')]
        sl = sl[!str_detect(sl,'HG')]
        sl = sl[!str_detect(sl,'MT')]
        seqlevels(gtf.l, pruning.mode='coarse') = sl

        gtf.pct = range(split(gtf, gtf$transcript_id))
        gtf.pct.tss = unlist(resize(gtf.pct, width=1, fix='start'))

    message('Annotating  ...')
        tss.dist      = as.data.table(distanceToNearest(rsa.tss.str, gtf.pct.tss, ignore.strand=FALSE))
        tss.dist$qs   = start(rsa.tss)[tss.dist$queryHits]
        tss.dist$qstr = as.character(strand(rsa.tss))[tss.dist$queryHits]
        tss.dist$ts   = start(gtf.pct.tss)[tss.dist$subjectHits]
        tss.dist$tstr = as.character(strand(gtf.pct.tss))[tss.dist$subjectHits]
        tss.dist$str.dist = tss.dist$distance
        tss.dist$str.dist[with(tss.dist, qs <= ts & tstr == '+' )] = tss.dist$str.dist[with(tss.dist, qs <= ts & tstr == '+' )] * -1
        tss.dist$str.dist[with(tss.dist, qs >= ts & tstr == '-' )] = tss.dist$str.dist[with(tss.dist, qs >= ts & tstr == '-' )] * -1
        tss.dist$str.dist.log = log10(tss.dist$distance)
        tss.dist$str.dist.log[tss.dist$str.dist < 0] = tss.dist$str.dist.log[tss.dist$str.dist < 0] * -1
        tss.dist$tid = names(gtf.pct.tss)[tss.dist$subjectHits]

        tss.dist$type = 'None'
        tss.dist$type[with(tss.dist, str.dist < 0 & abs(str.dist) < tss.dist.param)] = 'Divergent'
        tss.dist$type[with(tss.dist, str.dist > 0 & abs(str.dist) < tss.dist.param)] = 'Convergent'

        rsa$nearest.tss.dist = tss.dist$str.dist
        rsa$antisense.type   = tss.dist$type
        rsa$antisense.type[rsa$readthrough]   = 'None'
        rsa$antisense.type[rsa$antisense.type == 'None' & rsa$gene_body_anti.ind] = 'Internal'

    if(antisense.annot){
        message('Antisense - Divergent/Convergent ...')
            rsa.flip = subset(flipStrand(rsa.tss), !readthrough)
            rsa.dist = as.data.table(distanceToNearest(rsa.tss, rsa.flip))
            rsa.dist$antisense.type = rsa$antisense.type

            rsa.dist$qs   = start(rsa.tss)[rsa.dist$queryHits]
            rsa.dist$qstr = as.character(strand(rsa.tss))[rsa.dist$queryHits]

            rsa.dist$ts    = start(rsa.flip)[rsa.dist$subjectHits]
            rsa.dist$tstr = as.character(strand(rsa.flip))[rsa.dist$subjectHits]

            rsa.dist$str.dist = rsa.dist$distance
            rsa.dist$str.dist[with(rsa.dist, qs <= ts & tstr == '+' )] = rsa.dist$str.dist[with(rsa.dist, qs <= ts & tstr == '+' )] * -1
            rsa.dist$str.dist[with(rsa.dist, qs >= ts & tstr == '-' )] = rsa.dist$str.dist[with(rsa.dist, qs >= ts & tstr == '-' )] * -1
            rsa.dist$str.dist.log = log10(rsa.dist$distance)
            rsa.dist$str.dist.log[rsa.dist$str.dist < 0] = rsa.dist$str.dist.log[rsa.dist$str.dist < 0] * -1
            rsa.dist$type = 'None'
            rsa.dist$type[with(rsa.dist, str.dist < 0 & abs(str.dist) < 10000)] = 'A_Divergent'
            rsa.dist$type[with(rsa.dist, str.dist > 0 & abs(str.dist) < 10000)] = 'A_Convergent'
            rsa.dist$readthrough = rsa$readthrough
            rsa.dist = subset(rsa.dist, antisense.type=='None' & !readthrough)

            rsa$antisense.type[rsa.dist$queryHits] = rsa.dist$type
            rsa$antisense.type[rsa.dist$queryHits] = rsa.dist$type

            message('Antisense - Internal ...')
            fora = dtfindOverlaps(rsa, rsa.flip, ignore.strand=TRUE)
            fora.dist = as.data.table(distanceToNearest(rsa.tss, rsa.flip))

            fora$antisense.type = rsa$antisense.type[fora$queryHits]
            fora$readthrough    = rsa$readthrough[fora$queryHits]
            fora$qs             = start(rsa)[fora$queryHits]
            fora$ts             = start(rsa.flip)[fora$subject]
            fora$dist           = with(fora, abs(qs - ts))
            fora$width          = width(rsa)[fora$queryHits]
            fora$id1            = rsa$antisense_id[fora$queryHits]
            fora$id2            = rsa.flip$antisense_id[fora$subjectHits]

            fora = subset(fora, !readthrough & id1 != id2 & antisense.type=='None')

            rsa$antisense.type[fora$queryHits] = 'A_Internal'
    }
    return(rsa)
}

#//Antisense

# ---------------------------------------------------------------------------- #
# ---------------------------------------------------------------------------- #
#annotates the ranges with the corresponding list
setGeneric("AnnotateRanges",
           function(region, annotation,
                    ignore.strand=FALSE,
                    type='precedence',
                    null.fact='None',
                    collapse.char=':',
                    precedence=NULL,
					id.col=NULL)
               standardGeneric("AnnotateRanges") )

setMethod("AnnotateRanges",signature("GRanges","GRangesList"),
          function(region, annotation, ignore.strand=FALSE, type = 'precedence', null.fact = 'None',collapse.char=':'){

    if(! class(region) == 'GRanges')
        stop('Ranges to be annotated need to be GRanges')

    if(! all(sapply(annotation, class) == 'GRanges'))
        stop('Annotating ranges need to be GRanges')

    if(!type %in% c('precedence','all'))
        stop('type may only be precedence and all')

    require(data.table)
    require(GenomicRanges)
    message('Overlapping...\n')
    if(any(names(is.null(annotation))))
        stop('All annotations need to have names')

    if(class(annotation) != 'GRangesList')
        annotation = GRangesList(lapply(annotation, function(x){values(x)=NULL;x}))

    a = suppressWarnings(data.table(as.matrix(findOverlaps(region, annotation, ignore.strand=ignore.strand))))
    a$id = names(annotation)[a$subjectHits]
    a$precedence = match(a$id,names(annotation))
    a = a[order(a$precedence)]

    if(type == 'precedence'){
        message('precedence...\n')
        a = a[!duplicated(a$queryHits)]
        annot = rep(null.fact, length(region))
        annot[a$queryHits] = a$id
    }
    if(type == 'all'){
        message('all...\n')
        a = a[,list(id=paste(unique(id),collapse=collapse.char)),by='queryHits']
        annot = rep(null.fact, length(region))
        annot[a$queryHits] = a$id

    }
    return(annot)

})

setMethod("AnnotateRanges",signature("GRanges","list"),
          function(region, annotation, ignore.strand=FALSE, type = 'precedence', null.fact = 'None',collapse.char=':'){

		  if(!all(unlist(lapply(annotation, 'class')) == 'GRanges'))
			stop('all elements of annotation need to be GRanges objects')

			annotation = GRangesList(lapply(annotation, function(x){values(x)=NULL;x}))
			AnnotateRanges(region, annotation, ignore.strand, type, null.fact, collapse.char)

		  })



setMethod("AnnotateRanges",signature("GRanges","GRanges"),
          function(region, annotation, ignore.strand=FALSE, type = 'precedence', null.fact = 'None',collapse.char=':', precedence=NULL, id.col=NULL){

				if(is.null(id.col))
					stop('Annotation needs to have a specified id')

				if(is.null(values(annotation)[[id.col]]))
					stop('id.col is not a valid column')


				if(!is.null(precedence)){
                if(!all(precedence %in% annotation$id))
                    stop('all precednce leveles have to be in the annotation id')
				}else{
					type='all'
					message('type set to all when precedence is not defined')
				}

				if(!type %in% c('precedence','all'))
					stop('type may only be precedence and all')

				require(data.table)
				require(GenomicRanges)
                message('Overlapping...\n')
				if(any(names(is.null(annotation))))
					stop('All annotations need to have names')

				a = suppressWarnings(data.table(as.matrix(findOverlaps(region, annotation, ignore.strand=ignore.strand))))
				a$id = values(annotation)[[id.col]][a$subjectHits]


              if(type == 'precedence'){
                  message('precedence...\n')
                  a$precedence = match(a$id,precedence)[a$subjectHits]
                  a = a[order(a$precedence)]
                  a = a[!duplicated(a$queryHits)]

              }
              if(type == 'all'){
                  message('all...\n')
                  a = a[,list(id=paste(unique(id),collapse=collapse.char)),by='queryHits']
              }
			  annot = rep(null.fact, length(region))
              annot[a$queryHits] = a$id
              return(annot)

          })


# ---------------------------------------------------------------------------- #
# given a gtf file constructs the annotation list
GTFGetAnnotation = function(g, downstream=500, upstream=1000){

    g.exon = g[g$type=='exon']
    exon = unlist(g.exon)
    gene = unlist(range(split(g.exon, g.exon$gene_id)))
    tss  = promoters(gene, downstream=downstream, upstream=upstream)
    tts  = promoters(resize(gene, width=1, fix='end'), downstream=downstream,
                    upstream=upstream)
    intron = GenomicRanges::setdiff(gene, exon)

    values(exon) = NULL
    gl = GRangesList(tss    = tss,
                     tts    = tts,
                     exon   = exon,
                     intron = intron)

    return(gl)

}

# ---------------------------------------------------------------------------- #
# annotates a bam file with a given annotation list
Annotate_Reads = function(infile, annotation, ignore.strand=FALSE, ncores=8){

    require(doMC)
    registerDoMC(ncores)
    chrs = chrFinder(infile)
    # chrs = chrs[!chrs$chr %in% c('chrM','chrY'),]
    lchr = list()
    message('Looping ...')
    lchr = foreach(chr = chrs$chr)%dopar%{

        w = GRanges(chr, IRanges(1, chrs$chrlen[chrs$chr==chr]))
        reads = readGAlignments(infile, use.names=TRUE, param=ScanBamParam(which=w))
        g = granges(reads, use.names=TRUE, use.mcols=TRUE)
        if(length(g) == 0)
            return(data.table(rname=NA, annot=NA, uniq=NA))

        g$annot = suppressMessages(AnnotateRanges(g, annotation, ignore.strand=ignore.strand))
        g = g[order(match(g$annot, c(names(annotation),'None')))]
        dg = data.table(rname = names(g), annot=g$annot)
        dg[,uniq := .N, by=rname]
        dg[,uniq := ifelse(uniq == 1,'Uniq','Mult')]
        dg = split(dg, dg$annot)
        dg = dg[c(names(annotation),'None')]
        dg = rbindlist(dg)
        dg = dg[!duplicated(dg$rname)]
        return(dg)
    }
    message('Merging ...')
    ldg = rbindlist(lchr)
    ldg[,uniq := NULL]
    ldg[,uniq := .N, by=rname]
    ldg[,uniq := ifelse(uniq == 1,'Uniq','Mult')]
    ldg = split(ldg, ldg$annot)
    ldg = ldg[c(names(annotation),'None')]
    ldg = rbindlist(ldg)
    ldg = ldg[!duplicated(ldg$rname)]
    ldg = na.omit(ldg)

    sdg = data.table(experiment = BamName(infile),
                     ldg[,list(cnts=length(rname)), by=list(annot,uniq)])

    sdg[,freq:=round(cnts/sum(cnts),2)]
    return(sdg)
}


# ---------------------------------------------------------------------------- #
# Annotates a list of bam files with a given list of annotation
Annotate_Bamfiles = function(bamfiles, annotation, ignore.strand=FALSE, ncores=8){

    require(data.table)
    ld = list()
    for(i in 1:length(bamfiles)){
        bamfile = bamfiles[i]
        name = BamName(bamfile)
        message(name)
        ld[[name]] = Annotate_Reads(bamfile,
                                    annotation,
                                    ignore.strand=ignore.strand,
                                    ncores=ncores)

    }
    dd = rbindlist(ld)
    return(dd)
}


# ---------------------------------------------------------------------------- #
plot_Annotate_Bamfiles = function(dannot, outpath, outname, width=8, height=6, which=NULL){

    require(ggplot2)
    if(is.null(which))
        which=1:5

    if(is.null(theme))
        theme = theme(axis.text.x = element_text(angle = 90, hjust = 1),
                      axis.text.y = element_text(color='black'))

    colnames(dannot)[2] = 'Annotation'
    dannot$Annotation = factor(dannot$Annotation)

    dannot$experiment = factor(dannot$experiment)
    tot = dannot[,list(cnts=sum(cnts)),by=list(experiment,Annotation)]
    tot = merge(tot, tot[,list(tot=sum(cnts)),by=experiment],by='experiment')
    tot[,freq := round(cnts/tot, 2)]

    tot.uniq = subset(dannot, uniq=='Uniq')
    tot.uniq = merge(tot.uniq, tot.uniq[,list(tot=sum(cnts)),by=experiment],by='experiment')
    tot.uniq[,freq := cnts/tot]

    gl = list()

        gl$a=ggplot(tot, aes(x=experiment, y=cnts, fill=Annotation)) +
            geom_bar(stat='identity') +
            theme


        gl$b=ggplot(tot, aes(x=experiment, y=freq, fill=Annotation)) +
            geom_bar(stat='identity') +
            theme +
            ylim(c(0,1))

        gl$c=ggplot(dannot, aes(x=experiment, y=cnts, fill=Annotation)) +
            geom_bar(stat='identity') +
            facet_grid(~uniq) +
            theme

        gl$d=ggplot(dannot, aes(x=experiment, y=freq, fill=Annotation)) +
            geom_bar(stat='identity') +
            facet_grid(~uniq) +
            theme +
            ylim(0,1)

        gl$e=ggplot(tot.uniq, aes(x=experiment, y=freq, fill=Annotation)) +
            geom_bar(stat='identity') +
            theme +
            xlab('Sample Name') +
            ylab('Frequency') +
            ylim(0,1)

    browser()
    pdf(file.path(outpath, paste(DateNamer(outname),'pdf', sep='.')), width=width, height=height)
        lapply(gl[which], print)
    dev.off()

}


# ---------------------------------------------------------------------------- #
setGeneric("Get_Annotation",
           function(granges)
               standardGeneric("Get_Annotation") )

setMethod("Get_Annotation",signature("GRangesList"),
                         function(granges){


        Get_Annotation(unlist(granges))

})

setMethod("Get_Annotation",signature("GRanges"),
          function(granges){


              grl = split(granges, granges$gene_id)
              trl = split(granges, granges$transcript_id)
              grl.ranges = unlist(range(grl))
              trl.ranges = unlist(range(trl))

              dannot = as.data.frame(values(granges))

              message('Constructing annotation...')
              # annot = unique(GRangesTodata.frame(granges)[,c('gene_id','transcript_id','gene_name','gene_biotype')])
              vsub = c('gene_id','transcript_id')
              if('gene_name' %in% colnames(dannot))
                  vsub = c(vsub,'gene_name')

              if('gene_biotype' %in% colnames(dannot))
                  vsub = c(vsub,'gene_biotype')

              annot = unique(dannot[,vsub])
              annot$gcoord = as.character(grl.ranges)[annot$gene_id]
              annot$gwidth = width(grl.ranges)[annot$gene_id]
              annot$tcoord = as.character(trl.ranges)[annot$transcript_id]
              annot$twidth = sum(width(trl))[annot$transcript_id]

              return(annot)
})


# ---------------------------------------------------------------------------- #
#' Annotate_Peaks - given a peaks GRanges and a gtf file, annotates the peaks
#' with their corresponding locations
#'
#' @param peaks GRanges with peak location
#' @param annot annotation file
#'
#' @return annotatet GRanges
Annotate_Peaks = function(peaks, gtf, exon_id = 'exon', annot_id = 'annot',
                          colnames = c('gene_id','gene_name','gene_biotype','gcoord')){

    source(file.path(lib.path, 'Annotate_Functions.R'), local=TRUE)
    source(file.path(lib.path, 'ScanLib.R'), local=TRUE)
    message('Constructing annotation...')
        annot.l = GTFGetAnnotation(gtf[[exon_id]])


    message('Gene annotation...')
        peaks$gene.annot = suppressWarnings(AnnotateRanges(peaks, annot.l, type='precedence'))

    message('Getting gene names...')
        gtf.gens    = subset(gtf[[exon_id]], type=='exon')
        gtf.gens    = unlist(range(split(gtf.gens, gtf.gens$gene_id)))
        fog         = dtfindOverlaps(peaks, resize(gtf.gens, width=width(gtf.gens)+1000, fix='end'))
        fog$gene_id = names(gtf.gens)[fog$subjectHits]

        fogm = merge(fog, unique(gtf[[annot_id]][,colnames]), by='gene_id')
        fogm = fogm[,c('queryHits','gene_name','gene_id'),with=FALSE][,lapply(.SD, function(x)paste(unique(x), sep=':', collapse=':')),by='queryHits']
        fog$subjectHits=NULL

        peaks$gene_name = 'None'
        peaks$gene_name[fogm$queryHits] = fogm$gene_name

        peaks$gene_id = 'None'
        peaks$gene_id[fogm$queryHits]   = fogm$gene_id

    # message('Getting Associated Genes...')
    # foa = dtfindOverlaps(peaks, resize(gtf.gens, width=width(gtf.gens)+1000000, fix='center'))
    # foa$gene_id = names(gtf.gens)[foa$subjectHits]
    # foa$subjectHits = NULL
    # fol = split(foa, foa$queryHits)
    # foa = foa[,list(list(gene_id)),by=queryHits]
    # peaks$gene_id_assoc = 'None'
    # peaks$gene_id_assoc[foa$queryHits] = foa$V1

    return(peaks)

}

