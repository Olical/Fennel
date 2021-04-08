(local l (require :test.luaunit))
(local fennel (require :fennel))

(fn == [test expected]
  (let [opts (if (rawget _G :jit)
                 {:useBitLib true}
                 (and (not= _VERSION "Lua 5.1") (not= _VERSION "Lua 5.2"))
                 {})]
    ;; skip the test on PUC 5.1 and 5.2
    (when opts
      (l.assertEquals (fennel.eval test opts) expected))))

(fn test-shifts []
  (== "(lshift 33 2)" 132)
  (== "(lshift 1)" 2)
  (== "(rshift 33 2)" 8)
  (let [(ok? msg) (pcall fennel.compileString "(lshift)")]
    (l.assertFalse ok?)
    (l.assertStrContains msg "Expected more than 0 arguments")))

(fn test-ops []
  (== "(band 22 13)" 4)
  (== "(bor 1 2 4 8)" 15)
  (== "(bxor 1)" 1)
  (== "(band)" 0))

{: test-shifts
 : test-ops}
