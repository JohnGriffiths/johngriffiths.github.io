Title: Moving away from HDF5
Tags: python

In the research lab where I work, we've been developing a data processing pipeline for several years. This includes not only a program but also a new file format based on HDF5 for a specific type of data. While the choice of HDF5 was looking compelling on paper, we found many issues with it. **Recently, we decided to move away permanently from this format in our software**.

<!-- PELICAN_END_SUMMARY -->

**The first mistake we did was to design a file format in the first place**. This is an extremely hard problem, and the slightest mistake has huge and expensive consequences. This is better left off to dedicated working groups.

Why did we do it, then? There was previously a file format that had been used in many labs for years, but it was badly specified and it had many issues. It could happen that scientific results were wrong because the experimenter was confused by the format. There were also serious performance problems, and the format wouldn't have scaled to modern recording devices. In particular, it used text files for huge arrays. So we decided to design a new format around HDF5.

**HDF5 looked like an ideal choice**: widely-supported, supposedly fast and scalable, versatile. We couldn't find any argument against it.

We spent months and years designing the perfect HDF5-based file format that would work for everyone. We ran many benchmarks on various configurations to find the best compromise between design and performance. We rewrote our entire Python software around this new format using the [h5py library](http://www.h5py.org/). People around the world started to generate petabytes of data with our program.

That's when we started to see several problems: bugs in the HDF5 implementation and wrappers, corrupted files, many limitations of various kinds, poor performance, etc. Our users were upset. They couldn't do things they could do with the old format, however clunky it may have been. We implemented hacks and patches around these bugs and limitations, and ended up with an unmaintainable code mess.

At some point, we said stop. For us, **HDF5 was too much trouble, and we estimated that dropping it completely was the least painful choice**. With so much data in this format in the wild, we still need to provide support, conversion, and export facilities, but we encourage our users to move to a simpler format.

Let's now see in detail the problems we had with HDF5.

## Single implementation

**The [HDF5 specification](https://www.hdfgroup.org/HDF5/doc/H5.format.html) is very complex and low level**. It spans about **150 pages**. In theory, since the specification is open, anyone can write their own implementation. In practice, this is so complex that **there is a single implementation, spanning over 300,000 lines of C code**. The library may be hard to compile on some systems. There are wrappers in many languages, including Python. They all rely on the same C library, so they all share the bugs and performance issues of this implementation. Of course, the wrappers can add their own bugs and issues.

The code repository of the reference implementation is hard to find. It looks like there is an [unofficial GitHub clone](https://github.com/live-clones/hdf5) of an [SVN repository](https://svn.hdfgroup.uiuc.edu/hdf5/trunk/). There are no issues, pull requests, little documentation, etc. just a bunch of commits. To understand the code properly, you have to become very familiar with the 150 pages of specification.

**Overall, using HDF5 means that, to access your data, you're going to depend on a very complex specification and library, slowly developed over almost 20 years by a handful of persons, and which are probably understood by just a few people in the world**. This is a bit scary.

## Corruption risks

Corruption may happen if your software crashes while it's accessing an HDF5 file. Once a file is corrupted, all of your data is basically lost forever. **This is a major drawback of storing a lot of data in a single file, which is what HDF5 is designed for**. Users of our software have lost many hours of work because of this. Of course, you need to write your software properly to minimize the risk of crashes, but it is hard to avoid them completely. Some crashes are due to the HDF5 library itself.

To mitigate corruption issues, journaling was being considered in a future version of HDF5. I can find mentions of this feature on the mailing list, [for example here in 2008](http://hdf-forum.184993.n3.nabble.com/hdf-forum-Recover-a-corrupt-HDF5-file-td193622.html), or in [2012](http://hdf-forum.184993.n3.nabble.com/File-corruption-and-hdf5-design-considerations-td4025305.html). It was planned for the **1.10 version**, which itself was originally planned for [2011](https://lists.hdfgroup.org/pipermail/hdf-forum_lists.hdfgroup.org/2011-September/005059.html), if not earlier. Finally it looks like [**journaling is not going to make it into the 1.10 release**](https://hdfgroup.org/wp/2015/05/whats-coming-in-the-hdf5-1-10-0-release/) (see the *Comments* section). This release is currently planned for 2016, and the [very first alpha version has been released a few days ago](https://www.hdfgroup.org/HDF5/release/obtain5110.html).

[Anecdotally, this version seems to break compatibility in that *earlier releases [of HDF5] will not be able to read HDF5-1.10 files.* Also, there is a big warning for the alpha release: *PLEASE BE AWARE that the file format is not yet stable. DO NOT keep files created with this version.*]

## Various limitations and bugs

Once, we had to tell our Windows users to downgrade their version of h5py because a [segmentation fault occurred with variable-length strings](https://github.com/h5py/h5py/issues/593) in the latest version. This is one of the disadvantages of using a compiled library instead of a pure Python library. There is no other choice since the only known implementation of HDF5 is written in C.

[UTF-8 support in HDF5 seems limited](http://docs.h5py.org/en/latest/strings.html), so in practice you need to rely on ASCII to avoid any potential problems.

There are few supported data types for metadata attributes. In Python, if your attributes are in an unsupported type (for example, tuples), they might be silently serialized via pickle to an opaque binary blog, making them unreadable in another language like MATLAB.

A surprising limitation: **as of today, you still can't delete an array in an HDF5 file**. More precisely, you can delete the link, but the data remains in the file so that the file size isn't reduced. The only way around this is to make a copy of the file *without* the deleted array (for example with the *h5repack* tool). This is problematic when you have 1TB+ files. The upcoming HDF5 1.10 promises to fix this partially, but it is still in alpha stage at the time of this writing.

## Performance issues

Datasets can be stored in several ways in HDF5: **contiguously or chunked**. If the former, the data is stored in a contiguous buffer in the file. If the latter, the dataset is split uniformly in rectangular chunks organized in a B-tree.

If you use chunking, you need to be very careful with the [chunk size](http://www.speedup.ch/workshops/w37_2008/HDF5-Tutorial-PDF/HDF5-Cach-Buf.pdf) and your CPU cache size, otherwise you might end up with terrible performance. Optimizing performance with HDF5 is a [rather complicated topic](http://www.pytables.org/usersguide/optimization.html).

We essentially used uncompressed contiguous datasets in our software. Recently, I found out a simple trick to improve performance considerably with this type of data. [Here is an actual example](https://gist.github.com/rossant/7b4704e8caeb8f173084). When you have an uncompressed contiguous dataset, you can obtain the address of the first byte of the array in the file with a special HDF5 API call. If you know the shape and data type of the dataset, you can use NumPy to memory-map that buffer directly. By contrast, if you use h5py, the HDF5 library will be used to access all or part of the data.

**This trick can lead to staggering performance improvements: in the example above, using memmap instead of HDF5 leads to a 100x speed increase for read access**. In other words, in this particular situation, HDF5 seems to be two orders of magnitude slower than it should. I'd be curious to understand why.

This corresponds to what we've observed while we were using HDF5 extensively: **HDF5 can be particularly slow and, as such, it doesn't appear to be a good choice in performance-critical applications.**

## Lack of support on distributed architectures

HDF5 was designed at a time where [MPI was the state-of-the-art for high performance computing](http://www.dursi.ca/hpc-is-dying-and-mpi-is-killing-it/). Now, we have large-scale distributed architectures like Hadoop, Spark, etc. HDF5 isn't well supported on these systems. For example, on Spark, you have to [split your data into multiple HDF5 files](https://hdfgroup.org/wp/2015/03/from-hdf5-datasets-to-apache-spark-rdds/), which is precisely the opposite of what HDF5 encourages you to do (see also [this document](https://www.hdfgroup.org/pubs/papers/Big_HDF_FAQs.pdf) by the HDF Group).

By contrast, flat binary files are natively supported on Spark.

## Opacity

**You depend on the HDF5 library to do anything with an HDF5 file**. What is in a file? How many arrays there are? What are their paths, shapes, data types? What is the metadata? Without the HDF5 library, you can't answer any of these questions. Even when HDF5 is installed, you need dedicated tools or, worse, you need to write your own script. This adds considerable cognitive overhead when working with scientific data in HDF5.

A simpler and roughly equivalent alternative to HDF5 would be to store each array in its own file, within a sensible file hierarchy, and with the metadata stored in JSON or YAML files. For the file format of the individual arrays, one can choose for example a raw binary format without a header (`arr.tofile()` in NumPy), or the NumPy format [`.npy`](http://docs.scipy.org/doc/numpy-dev/neps/npy-format.html) which is just a flat binary file with a fixed-length ASCII header. [Note the paragraph about HDF5 in the page linked here] These files can be easily memory-mapped with very good performance since the file system and the OS are in charge in that case.

This leads to a self-documenting format that anyone can immediately explore with any command-line shell, on any computer on the planet, with any programming language, without installing anything, and without reading any specific documentation. In 20 or 30 years, your files are much more likely to be readable if they are stored in this format than if they're stored in HDF5.

## Philosophy

**HDF5 encourages you to put within a single file many data arrays corresponding to a given experiment or trial**. These arrays are organized in a POSIX-like structure, where files are arrays (also called *datasets*) and folders are *groups*.

File systems are insanely complex. They have been designed, refined, battle-tested, and optimized over decades by many experts. As such, despite their complexity, they're generally very robust. They're also highly efficient, and they implement advanced caching strategies. It's almost impossible to beat file systems, so HDF5 is just more limited and less efficient.

What's the point?

If you replace your HDF5 file by a hierarchy of flat binary files and text files, as described in the previous section, you obtain a file format that is more robust, more powerful, more efficient, more maintainable, more transparent, and more amenable to distributed systems than HDF5.

Surely, there must be advantages in using HDF5 over this more rudimentary file organization, otherwise there wouldn't be an entire community around HDF5, but I can't find them. I'd be curious to hear counter-arguments.