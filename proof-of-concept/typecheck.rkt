#lang typed/racket

(require "ast.rkt")

(: consistent? (-> Type Type Boolean))
(define (consistent? T1 T2)
  (match `(,T1 ,T2)
    [`(,T1 dynamic) #t]
    [`(dynamic ,T2) #t]
    [`(,(arrow T1-dom T1-cod) ,(arrow T2-dom T2-cod))
     (and (consistent-list? T1-dom T2-dom)
          (consistent-list? T1-cod T2-cod))]
    [else (equal? T1 T2)]))

(: consistent-list? (-> (Listof Type) (Listof Type) Boolean))
(define (consistent-list? lot1 lot2)
  (andmap consistent? lot1 lot2))

(: typeof (-> Constant Type))
(define (typeof c)
  (match c
    [(int n) 'int]
    [(bool b) 'bool]
    [(str s) 'string]
    [else (error 'typeof "not implemented")]))

(define-type Env (Listof (Pair Symbol Type)))

(: typecheck (-> Env Pgrm Env))
(define (typecheck env p)
  (match p
    ['() env]
    [(cons first rest)
     (local [(define type-env (typecheck-stmt env first))]
       (typecheck type-env rest))]))

(: typecheck-stmt (-> Env Stmt Env))
(define (typecheck-stmt env s)
  (match s
    [(decl name type)
     (cons (cons name type) env)]
    [(assn names expr)
     (local [(define expect-types
               ((inst map Type Symbol)
                (lambda (name)
                  (local [(define result (assoc name env))]
                    (if (false? result)
                        (error 'typecheck-stmt "Unbound identifier")
                        (cdr result))))
                names))
             (define expect-length (length expect-types))
             (define actual-types
               (local [(define original (typecheck-expr env expr))
                       (define listify (if (list? original)
                                           original
                                           (list original)))
                       ]
                 (if (> (length listify) expect-length)
                     (take listify expect-length)
                     listify)))
             (define actual-length (length actual-types))]
       (cond
         [(not (= expect-length actual-length))
          (error 'typecheck-stmt "Assignment arity mismatch")]
         [(consistent-list? expect-types actual-types) env]
         [else (error 'typecheck-stmt "Assignment type mismatch")]))]
    [(func name args rets body)
     (and (typecheck (append rets (append args env)) body)
          (local [(define inst-map (inst map Type (Pair Symbol Type)))]
            (cons (cons name
                        (arrow (inst-map cdr args)
                               (inst-map cdr rets)))
                  env)))]
    [(if-stmt cond then else)
     (local [(define cond-type (typecheck-expr env cond))]
       (if (equal? cond-type 'bool)
           (begin (typecheck env then)
                  (typecheck env else)
                  env)
           (error 'typecheck-stmt "If condition not a Boolean")))]
    [else
     (begin (typecheck-expr env (cast s Expr))
            env)]))

(: typecheck-expr (-> Env Expr Type))
(define (typecheck-expr env e)
  (match e
    [(id name)
     (local [(define result (assoc name env))]
       (if (false? result)
           (error 'typecheck-expr "Unbound identifier")
           (cdr result)))]
    [(int i) 'int]
    [(bool b) 'bool]
    [(str s) 'string]
    [(int-binop n op lhs rhs)
     (if (and (consistent? (typecheck-expr env lhs) 'int)
              (consistent? (typecheck-expr env rhs) 'int))
         'int
         (error 'typecheck-expr "Apply integer binary operation with non-int values"))]
    [(bool-binop n op lhs rhs)
     (if (and (consistent? (typecheck-expr env lhs) 'bool)
              (consistent? (typecheck-expr env rhs) 'bool))
         'bool
         (error 'typecheck-expr "Apply Boolean binary operation with non-bool values"))]
    [(int-compop n op lhs rhs)
     (if (and (consistent? (typecheck-expr env lhs) 'int)
              (consistent? (typecheck-expr env rhs) 'int))
         'bool
         (error 'typecheck-expr "Apply integer comparison operation with non-int values"))]
    [(string-compop n op lhs rhs)
     (if (and (consistent? (typecheck-expr env lhs) 'string)
              (consistent? (typecheck-expr env rhs) 'string))
         'bool
         (error 'typecheck-expr "Apply string comparison operation with non-string values"))]
    [(app fun args)
     (local [(define fun-type (typecheck-expr env fun))]
       (if (or (arrow? fun-type) (equal? fun-type 'dynamic))
           (local [(define expect-types (fun-dom fun-type))
                   (define actual-types (typecheck-list env args))
                   (define expect-length (length expect-types))
                   (define actual-length (length actual-types))
                   (define adjusted-actual
                     (cond
                       [(> actual-length expect-length)
                        (take actual-types expect-length)]
                       [(< actual-length expect-length)
                        (append actual-types
                                (build-list (- expect-length actual-length)
                                            (lambda (x) 'dynamic)))]
                       [else actual-types]))
                   (define return-types (fun-cod fun-type))]
             (if (consistent-list? expect-types adjusted-actual)
                 return-types
                 (error 'typecheck-expr "Function application argument type mismatch")))
           (error 'typecheck-expr "Try to apply a non-function")))]))

(: typecheck-list (-> Env (Listof Expr) (Listof Type)))
(define (typecheck-list env es)
  ((inst map Type Expr)
   (lambda (e) (typecheck-expr env e))
   es))

(: fun-dom (-> Type (Listof Type)))
(define (fun-dom fun-type)
  (cond
    [(arrow? fun-type) (arrow-dom fun-type)]
    [(equal? fun-type 'dynamic) '(dynamic)]
    [else (error 'fun-dom "Try to get the domain of a non-function")]))

(: fun-cod (-> Type (Listof Type)))
(define (fun-cod fun-type)
  (cond
    [(arrow? fun-type) (arrow-cod fun-type)]
    [(equal? fun-type 'dynamic) '(dynamic)]
    [else (error 'fun-cod "Try to get the co-domain of a non-function")]))
