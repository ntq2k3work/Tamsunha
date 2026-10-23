<?php

namespace App\Exceptions;

use RuntimeException;

final class RpcError extends RuntimeException
{
    public function __construct(
        public readonly string $errorCode,
        string $message = '',
        public readonly bool $retryable = false,
        public readonly int $httpStatus = 422,
    ) {
        parent::__construct($message === '' ? $errorCode : $message);
    }

    /** @return array{code: string, message: string, retryable?: bool} */
    public function toEnvelope(): array
    {
        $error = [
            'code' => $this->errorCode,
        ];

        if ($this->getMessage() !== $this->errorCode) {
            $error['message'] = $this->getMessage();
        }

        if ($this->retryable) {
            $error['retryable'] = true;
        }

        return $error;
    }
}
