package com.hamrah.app.core

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ParserFixturesTest {

    private fun fixturesDir(): File {
        val candidates = listOf(
            File("../../test/fixtures/sms"),
            File("test/fixtures/sms"),
            File("../test/fixtures/sms"),
            File("fixtures/sms")
        )
        return candidates.firstOrNull { it.isDirectory }
            ?: error("test/fixtures/sms not found; candidates=${candidates.map { it.absolutePath }}")
    }

    @Test
    fun allAppendixAFixturesMatch() {
        val failures = FixtureChecks.run(fixturesDir())
        assertTrue(failures.joinToString(separator = "\n"), failures.isEmpty())
    }

    @Test
    fun senderCanonicalizationIsStable() {
        val forms = listOf("+989999987641", "00989999987641", "989999987641", "09999987641")
        val canonical = forms.map { Normalizer.canonicalSender(it) }.toSet()
        assertTrue("canonical forms differ: $canonical", canonical.size == 1)
    }
}
