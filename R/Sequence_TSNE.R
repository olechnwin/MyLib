
# ---------------------------------------------------------------------------- #
# does tsne dimensionallity reduction on sequence kmer

calculate_kmers = function(seq.all,
                           width=6,
                           normalize=TRUE,
                           reverse.complement=TRUE,
                           smooth=FALSE,
                           alpha=.3,
                           iter=100, 
                           smoothfun='smoothKmers'){

    if(class(seq.all) != 'DNAStringSet')
        stop('ds needs to be DNAStringSet')


    ss = seq(1, length(seq.all), by=10000)
    ds = data.frame(x=c(1,ss[-1]+1), y=c(tail(ss,-1),length(seq.all)))
    set.seed(1)

    require(data.table)
    # ------------------------------------------------- #
    message('Kmers...')
    lk = list()
    for(i in 1:nrow(ds)){
        print(i)
        lk[[as.character(i)]] = data.table(oligonucleotideFrequency(seq.all[ds[i,1]:ds[i,2]], width=width, as.prob=FALSE, step=1))
    }
    kmers = rbindlist(lk)
    knams = colnames(kmers)

    if(reverse.complement){
        message('Revcomp...')
        
        dk = data.frame(k1=colnames(kmers), k2=as.character(reverseComplement(DNAStringSet(colnames(kmers)))))
        dk = dk[!duplicated(apply(dk,1, function(x)paste(sort(x),collapse=':'))),]
        lk = list()
        for(i in 1:nrow(dk)){
            if(dk[i,1] != dk[i,2]){
                lk[[dk[i,1]]] = rowSums(kmers[,colnames(kmers) %in% dk[i,,drop=T],with=FALSE])
            }else{
                lk[[dk[i,1]]] = kmers[,colnames(kmers) == dk[i,1],with=FALSE]
            }
        }
        kmers = data.table(data.frame(lk))
        knams = dk$k1
        
    }

    message('Normalization...')
    kmers = kmers/rowSums(kmers)
    if(smooth){
        smoothfun = match.fun(smoothfun)
        kmers = smoothfun(kmers,
          width=width,
          alpha=alpha,
          iter=iter)
    }

    if(normalize)
        kmers = log((kmers+1)/exp(rowMeans(log(kmers+1))))
    message('Colnames...')
    colnames(kmers) = knams
    
    message('Returning...')
    return(as.matrix(kmers))

}

# ---------------------------------------------------------------------------- #
smoothKmers =  function(kmers, width, alpha=0.3, iter=10, plot){

    if(width > 6)
        stop('with > 6 is not supported')

    require(Biostrings)
    str = mkAllStrings(c('A','C','G','T'), width)
    A = as.matrix(stringDist(str, method='hamming'))
    A[A > 1] = 0
    A = A/colSums(A)
    
  kmers.0 = as.matrix(kmers)
  kmers.smooth = kmers.0
  lnorm = list()
  lnorm[['0']] = kmers.0
  for(i in 1:iter){
      kmers.smooth = alpha*(kmers.smooth%*%A) + (1-alpha)*(kmers.0)
      lnorm[[as.character(i)]] = kmers.smooth
  }
  lnorm = lapply(2:length(lnorm), function(x)sum((lnorm[[x]] - lnorm[[x-1]])^2))
  dnorm = data.frame(iter=seq_along(lnorm), norm=unlist(lnorm))
  attr(kmers.smooth,'norm') = dnorm
  return(kmers.smooth)

}

# ---------------------------------------------------------------------------- #
smoothKmersTime =  function(kmers, width, alpha=0.3, iter=10, plot){
    
    if(width > 6)
        stop('with > 6 is not supported')
    
    require(Biostrings)
    str = mkAllStrings(c('A','C','G','T'), width)
    A = as.matrix(stringDist(str, method='hamming'))
    A[A > 1] = 0
    A = A/colSums(A)
    
    kmers.0 = as.matrix(kmers)
    kmers.smooth = kmers.0
    for(i in 1:iter){
        kmers.smooth = alpha*(kmers.smooth%*%A) + (1-alpha)*(kmers.0)
        alpha = alpha/2
        
    }
    return(data.table(kmers.smooth))
    
}

# ---------------------------------------------------------------------------- #
smoothKmers_plot =  function(kmers, kwidth=5, alpha=0.3, iter=100,
  outpath, outname, width=4, height=4){

    require(ComplexHeatmap)
    require(circlize)
    if(kwidth > 6)
        stop('with > 6 is not supported')

    message('Matrix...')
    require(Biostrings)
    str = mkAllStrings(c('A','C','G','T'), kwidth)
    A = as.matrix(stringDist(str, method='hamming'))
    A[A > 1] = 0
    A = A/colSums(A)

    message('Smoothing...')
    pdf(file.path(outpath, DateNamer(paste(outname,'k', kwidth, 'a', alpha, 'i', iter, 'pdf', sep='.'))),
    width=width, height=height)
      kmers.0 = as.matrix(kmers)
      kmers.smooth = kmers.0
      for(i in 1:iter){
        message(i)
        kmers.smooth = alpha*(kmers.smooth%*%A) + (1-alpha)*(kmers.0)
        h=Heatmap(kmers.smooth, cluster_columns=FALSE, cluster_rows=FALSE,
                col = colorRamp2(c(0, max(kmers)), c("white", "red")),
                show_column_names=FALSE)
        draw(h)
      }
    dev.off()


}



# ---------------------------------------------------------------------------- #
get_tsne = function(kmers, coldata, per=30, dims=3){

  message('tsne...')
  require(Rtsne)
  coldata = coldata[!duplicated(kmers),]
  kmers = kmers[!duplicated(kmers),]
  ktsne = Rtsne(kmers, perplexity=per, dims=dims)
  dat = data.frame(ktsne$Y, coldata)
  colnames(dat)[1:dims] = paste('X', 1:dims, sep='')
  return(dat)

}
# ---------------------------------------------------------------------------- #

plot_tsne = function(ldat, color=NULL, shape=NULL, path.out, outname=NULL, 
                     size=.8, width=25, height=8){

  require(cowplot)
  require(ggplot2)
  if(is.null(outname))
    outname=attr(ldat,'outname')

  message('Plotting...')
  pdf(file.path(path.out, DateNamer(paste(outname,'pdf', sep='.'))),width=width, height=height)

    for(i in 1:length(ldat)){

      name = names(ldat)[i]
      dat = ldat[[name]]
      message(name)
      gl=list(
          g1=ggplot(dat, aes_string('X1','X2', color=color, shape=shape)) +
              geom_point(size=size) +
              ggtitle(paste('X - Y')),
          g2=ggplot(dat, aes_string('X3','X2', color=color, shape=shape)) +
              geom_point(size=size) +
              ggtitle(paste('Z - Y')),
          g3=ggplot(dat, aes_string('X2','X1', color=color, shape=shape)) +
              geom_point(size=size) +
              ggtitle(paste('X - Z'))
      )
      grobs = ggplotGrob(gl[[1]])$grobs
      gl = lapply(gl, function(x)x + theme(legend.position="none"))
      legend = grobs[[which(sapply(grobs, function(x) x$name) == "guide-box")]]

      pg = plot_grid(plotlist=gl, nrow=1, ncol=3)
      pg = plot_grid( pg, legend, rel_widths = c(9, .3))
      title = ggdraw() + draw_label(name, fontface='bold')
      pg = plot_grid(title, pg, ncol=1, rel_heights=c(0.1, 1))
      print(pg)
    }

  dev.off()
}


# ---------------------------------------------------------------------------- #
compare_Clusters = function(kmer, clust.ind='set'){

    require(flexclust)
    wdist = lapply(unique(kmer[[clust.ind]]),
                  function(x)dist(kmer[kmer[[clust.ind]]==x,1:3]))

    kmer.s = split(kmer[,1:3], kmer[[clust.ind]])
    bdist  = dist2(kmer.s[[1]], kmer.s[[2]])

    data.table(w.mean   = mean(unlist(wdist)),
               w.median = median(unlist(wdist)),
               w.max    = max(unlist(wdist)),
               w.min    = min(unlist(wdist)),
               b.mean   = mean(unlist(bdist)),
               b.median = median(unlist(bdist)),
               b.max    = max(unlist(bdist)),
               b.min    = min(unlist(bdist)))
}


# ---------------------------------------------------------------------------- #
run_kmerTSNE = function(seq,
                        coldata,
                        kmer.width = 4,
                        reverse.complement=TRUE,
                        normalize=TRUE,
                        smooth=FALSE,

                        perplexity=30,
                        alpha = .3,
                        iter=10,

                        path.out,
                        outname,
                        ncores=8,
                        color=NULL,
                        shape=NULL,
                        size=0.8){


    require(doMC)
    registerDoMC(ncores)
    message('Outname...')
    if(normalize)
        outname=paste(outname, 'gnorm', sep='.')

    if(reverse.complement)
        outname=paste(outname, 'rc', sep='.')

    if(smooth)
        outname=paste(outname, 'sm', iter, alpha, sep='.')

        outname=paste(outname, paste0('kw', kmer.width),sep='.')


    #
    message('kmers...')
    kmers = calculate_kmers(seq,
                            kmer.width,
                            normalize=normalize,
                            reverse.complement=reverse.complement,
                            smooth=smooth,
                            alpha=alpha,
                            iter=iter)


    #
    message('Selection...')
    var = apply(kmers, 2, sd)
    kmer.list = list(k.all     = kmers,
                     k.sel.var = kmers[, var > median(var)],
                     k.sel.10  = kmers[, order(-var)][,1:min(10, ncol(kmers))],
                     k.sel.100 = kmers[, order(-var)][,1:min(100,ncol(kmers))],
                     k.sel.500 = kmers[, order(-var)][,1:min(500,ncol(kmers))])

    ltsne = lapply(names(kmer.list), function(x){
                    get_tsne(kmer.list[[x]],
                             coldata,
                             per=perplexity)})
    names(ltsne) = names(kmer.list)

    # dtsne = lapply(ltsne,compare_Clusters(ltsne))

    # dtsne$set = names(ltsne)
    # dtsne$kmer.width = kmer.width
    # dtsne$smooth     = smooth
    # dtsne$alpha      = alpha
    # dtsne$iter       = iter

    attr(ltsne, 'outname')  = outname
    if(!all(c(color, shape) %in% colnames(coldata)))
        stop('coldata is missing columns')

    message('Plotting...')
    plot_tsne(ltsne,path.out=path.out, color=color, shape=shape, size=size)
    invisible(ltsne)

}



# ---------------------------------------------------------------------------- #
run_SmoothTest = function(seq,
                         kmer.width = 4,
                        reverse.complement=TRUE,
                        normalize=TRUE,
                        alpha = .3,
                        iter=10,
                        
                        path.out,
                        outname='SmoothTest', 
                        smoothfun='smoothKmers'){
    
    require(doMC)
    registerDoMC(ncores)
    message('Outname...')
    
    outname=paste(outname, smoothfun, sep='_')
    if(normalize)
        outname=paste(outname, 'gnorm', sep='.')
    
    if(reverse.complement)
        outname=paste(outname, 'rc', sep='.')
    
    outname=paste(outname, 'sm', sep='.')
    outname=paste(outname, paste0('kw', kmer.width),sep='.')
    
    pdf(file.path(path.out, paste(outname, 'pdf', sep='.')), width=5, height=5)
        for(a in alpha){
            for(i in iter){
                message(paste(a, i))
    
            kmers = calculate_kmers(seq,
                            kmer.width,
                            normalize=normalize,
                            reverse.complement=reverse.complement,
                            smooth=TRUE,
                            alpha=a,
                            iter=i, 
                            smoothfun=smoothfun)
            kmers = kmers
            var = apply(kmers, 2, sd)
            sum = colSums(kmers)
            d = data.frame(sum=sum, var=var, text=colnames(kmers))
            # d[,1:2]  = scale(d[,1:2])
            g=ggplot(d, aes(x=sum, y=var, label=text)) + geom_text(size=1) +
                # geom_text(data=subset(d, sum+var>1), color='red', size=1) +
                ggtitle(paste('alpha:', a, 'iter:',i))
            print(g)
            g=ggplot(attr(kmers,'norm'), aes(x=iter, y=norm)) + geom_point(size=.8)
                # geom_text(data=subset(d, sum+var>1), color='red', size=1) +
            print(g)
            
            }
        }
    dev.off()
}
        
    