/**
* TLS Sequence Number Handling
* 
* Copyright:
* (C) 2012 Jack Lloyd
* (C) 2014-2015 Etienne Cimon
*
* License:
* Botan is released under the Simplified BSD License (see LICENSE.md)
*/
module botan.tls.seq_numbers;

import botan.constants;
static if (BOTAN_HAS_TLS):
package:

import botan.utils.types;
import std.exception;
import memutils.hashmap;


interface ConnectionSequenceNumbers
{
public:
    abstract void newReadCipherState();
    abstract void newWriteCipherState();

    abstract ushort currentReadEpoch() const;
    abstract ushort currentWriteEpoch() const;

    abstract ulong nextWriteSequence(ushort);
    abstract ulong nextReadSequence();

    abstract bool alreadySeen(ulong seq) const;
    abstract void readAccept(ulong seq);
}

final class StreamSequenceNumbers : ConnectionSequenceNumbers
{
public:
    override void newReadCipherState() { m_read_seq_no = 0; m_read_epoch += 1; }
    override void newWriteCipherState() { m_write_seq_no = 0; m_write_epoch += 1; }

    override ushort currentReadEpoch() const { return m_read_epoch; }
    override ushort currentWriteEpoch() const { return m_write_epoch; }

    override ulong nextWriteSequence(ushort) { return m_write_seq_no++; }
    override ulong nextReadSequence() { return m_read_seq_no; }

    override bool alreadySeen(ulong) const { return false; }
    override void readAccept(ulong) { m_read_seq_no++; }
private:
    ulong m_write_seq_no = 0;
    ulong m_read_seq_no = 0;
    ushort m_read_epoch = 0;
    ushort m_write_epoch = 0;
}

final class DatagramSequenceNumbers : ConnectionSequenceNumbers
{
public:
    this() { m_write_seqs[0] = 0; }

    override void newReadCipherState() { m_read_epoch += 1; }

    override void newWriteCipherState()
    {
        m_write_epoch += 1;
        m_write_seqs[m_write_epoch] = 0;
    }

    override ushort currentReadEpoch() const { return m_read_epoch; }
    override ushort currentWriteEpoch() const { return m_write_epoch; }

    override ulong nextWriteSequence(ushort epoch) 
    { 
        ulong* i = epoch in m_write_seqs;
        assert(i !is null, "Found epoch");
        return ((cast(ulong) epoch) << 48 ) | ((*i)++);
    }

    override ulong nextReadSequence()
    {
        throw new Exception("DTLS uses explicit sequence numbers");
    }

    override bool alreadySeen(ulong sequence) const
    {
        const size_t window_size = (m_window_bits).sizeof * 8;

        if (sequence > m_window_highest)
            return false;

        const ulong offset = m_window_highest - sequence;

        if (offset >= window_size)
            return true; // really old?

        return (((m_window_bits >> offset) & 1) == 1);
    }

    override void readAccept(ulong sequence)
    {
        const size_t window_size = (m_window_bits).sizeof * 8;

        if (sequence > m_window_highest)
        {
            const size_t offset = cast(size_t)(sequence - m_window_highest);
            m_window_highest += offset;

            if (offset >= window_size)
                m_window_bits = 0;
            else
                m_window_bits <<= offset;

            m_window_bits |= 0x01;
        }
        else
        {
            const ulong offset = m_window_highest - sequence;
            m_window_bits |= (cast(ulong)(1) << offset);
        }
    }

private:
    HashMap!(ushort, ulong) m_write_seqs;
    ushort m_write_epoch;
    ushort m_read_epoch;
    ulong m_window_highest;
    ulong m_window_bits;
}